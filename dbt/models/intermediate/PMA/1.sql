CREATE OR REPLACE VIEW FIN_CON_SBX.INT_PORTFOLIO_SIMPLIFICATION.INT_PORTFOLIO_SKU_SIMPLIFICATION AS 
with std_cost_agg as (
    select
        plant,
        currency as std_cost_currency,
        ltrim(material, '0') as std_material,
        to_char(costing_date, 'yyyymm') as costing_month,
        sum(
            case
                when upper(trim(cost_component_description)) = 'RAW MATERIALS' then ( -- FIX #5: case-insensitive match (source spells 'Raw materials')
                    coalesce(fixed_value, 0) + coalesce(variable_value, 0)
                )::number(38, 6)
                else 0
            end
        ) as total_raw_material,
        sum(
            case
                when upper(trim(cost_component_description)) = 'PACKAGING MATERIALS' then ( -- FIX #5: case-insensitive match (source spells 'Packaging materials')
                    coalesce(fixed_value, 0) + coalesce(variable_value, 0)
                )::number(38, 6)
                else 0
            end
        ) as total_packaging_material,
        sum(
            case
                when upper(trim(cost_component_description)) in ('CONVERSION EXPENSE', 'CONVERSION LABOR') then ( -- FIX #5: same treatment for consistency; result unchanged
                    coalesce(fixed_value, 0) + coalesce(variable_value, 0)
                )::number(38, 6)
                else 0
            end
        ) as total_conversion_cost
    from
        FIN_CON.SCFIN.VIZ_PRODUCT_STANDARD_COST
    where
        costing_date >= '2025-01-01'
    group by
        ltrim(material, '0'),
        plant,
        to_char(costing_date, 'yyyymm'),
        currency
),
std_cost_qtr as (
    select
        std_material,
        plant,
        std_cost_currency,
        left(costing_month, 4) || 'Q' || to_varchar(ceil(right(costing_month, 2)::number / 3)) as costing_quarter,
        avg(total_raw_material) as total_raw_material,
        avg(total_packaging_material) as total_packaging_material,
        avg(total_conversion_cost) as total_conversion_cost,
        count(distinct costing_month) as std_cost_months_used
    from
        std_cost_agg
    group by
        std_material,
        plant,
        std_cost_currency,
        left(costing_month, 4) || 'Q' || to_varchar(ceil(right(costing_month, 2)::number / 3))
),
currency_conversion as (
    select
        upper(trim(from_currency)) as from_currency,
        upper(trim(to_currency)) as to_currency,
        right(monthyear, 4) || left(monthyear, 2) as conv_month,
        coalesce(
            case
                when upper(trim(from_currency)) = 'USD' then 1
                else (
                    coalesce(exchange_rate, 0) * (
                        coalesce(to_currency_ratio, 0) / nullif(from_currency_ratio, 0)
                    )
                ) / nullif(currdec_x, 0)
            end,
            1
        ) as conversion_rate
    from
        FIN_CUR.MASTERDATA.DIM_CURRENCY_CONVERSION
    where
        upper(trim(to_currency)) = 'USD'
        and upper(trim(exchange_rate_type)) = 'CPPE'
),
finance_step_1 as (
    select
        m.*,
        sc.* exclude (
            std_material,
            plant,
            costing_quarter
        ),
        curr.from_currency,
        curr.to_currency,
        curr.conv_month,
        case
            when upper(trim(sc.std_cost_currency)) = 'USD' then 1
            else curr.conversion_rate
        end as conversion_rate
    from
        SC_CON_SBX.PORTFOLIO_SIMPLIFICATION.RPT_SC_PORTFOLIO as m
        left join std_cost_qtr as sc on m.cos_vol_material_id = sc.std_material
        and m.cos_vol_plant = sc.plant
        and sc.costing_quarter = greatest(
            '2026Q3',
            to_varchar(
                year(
                    dateadd(
                        quarter,
                        -1,
                        to_date(
                            to_varchar(m.cos_vol_posting_month) || '01',
                            'YYYYMMDD'
                        )
                    )
                )
            ) || 'Q' || to_varchar(
                quarter(
                    dateadd(
                        quarter,
                        -1,
                        to_date(
                            to_varchar(m.cos_vol_posting_month) || '01',
                            'YYYYMMDD'
                        )
                    )
                )
            )
        )
        left join currency_conversion as curr on upper(trim(sc.std_cost_currency)) = curr.from_currency
        and m.cos_vol_posting_month = curr.conv_month
    where
        m.cos_vol_posting_month >= '202501'
),
customer_data as (
    select
        distinct c.name as customer_name,
        c.customer_name_level_one,
        c.customer_id_level_one,
        c.customer_name_level_two,
        c.customer_id_level_two,
        c.customer_name_level_three,
        c.customer_id_level_three,
        c.customer_name_level_four,
        c.customer_id_level_four,
        c.customer_name_level_five,
        c.customer_id_level_five,
        c.sales_organization,
        c.customer_group,
        c.customer_group_description,
        c.customer_type,
        c.customer_type_description,
        c.global_name,
        c.global_name_description,
        c.multinational_name,
        c.multinational_name_description,
        trim(c.customer_id) as customer_id,
        upper(trim(c.remote_system)) as remote_system
    from
        MD_CON.CUSTOMER.RPT_CUSTOMER_SALES_ORGANIZATION as c
    where
        exists (
            select
                1 as exists_flag
            from
                MD_CON.CUSTOMER.RPT_CUSTOMER as rm
            where
                trim(rm.customer_id) = trim(c.customer_id)
        )
        and upper(trim(c.remote_system)) not in ('CA', 'CAP') qualify row_number() over (
            partition by c.customer_id,
            c.sales_organization
            order by
                case
                    when c.partner_function = 'AG' then 1
                    else 2
                end,
                c.partner_counter,
                c.partner_function
        ) = 1
),
pnl_raw as (
    select
        p.calendar_year,
        p.calendar_month,
        p.currency,
        p.sold_to,
        nullif(trim(p.sales_group), '') as sales_group,
        nullif(trim(p.sales_office), '') as sales_office,
        p.sales_organization,
        p.kpi,
        p.VALUE_TYPE,
        p.country,
        p.country_description,
        p.sub_division_description,
        p.divisions_description,
        p.COMPANY_CODE,
        p.customer_group_one,
        c.customer_id,
        c.customer_name,
        c.customer_name_level_one,
        c.customer_id_level_one,
        c.customer_name_level_two,
        c.customer_id_level_two,
        c.customer_name_level_three,
        c.customer_id_level_three,
        c.customer_name_level_four,
        c.customer_id_level_four,
        c.customer_name_level_five,
        c.customer_id_level_five,
        c.customer_group,
        c.customer_group_description,
        c.customer_type,
        c.customer_type_description,
        c.global_name,
        c.global_name_description,
        c.multinational_name,
        c.multinational_name_description,
        c.remote_system,
        nullif(trim(p.customer_type_description), '') as pnl_customer_type_description,
        p.material as material_id,
        p.metric_value_usd::number(38, 4) as metric_value_usd,
        trim(
            case
                when regexp_like(p.sold_to, '^[0-9]+$') then ltrim(p.sold_to, '0')
                else p.sold_to
            end
        ) as pnl_customer_id,
        case
            when upper(trim(p.source_system)) = 'LP' then 'LAP'
            when upper(trim(p.source_system)) = 'NA' then 'LAP'
            when upper(trim(p.source_system)) = 'HP' then 'HUP'
            when upper(trim(p.source_system)) = 'CA' then 'CAP'
            when upper(trim(p.source_system)) = 'EP' then 'CCP'
            else upper(trim(p.source_system))
        end as pnl_remote_system
    from
        FIN_CON.COMMFIN_PNL.VIZ_PNL_DETAIL_KPIS as p
        left join customer_data as c on trim(
            case
                when regexp_like(p.sold_to, '^[0-9]+$') then ltrim(p.sold_to, '0')
                else p.sold_to
            end
        ) = trim(c.customer_id)
        and upper(trim(p.sales_organization)) = upper(trim(c.sales_organization))
    where
        p.kpi in ('Net Sales', 'Gross Profit Margin')
        and p.calendar_year >= 2025
        and p.global_version = 'ACT'
        and upper(trim(p.source_system)) in ('NA', 'LP', 'LAP')
),
pnl as (
    select
        p.material_id,
        p.calendar_year,
        p.calendar_month,
        p.currency,
        p.sold_to,
        p.sales_organization,
        p.pnl_remote_system,
        p.country,
        p.country_description,
        p.sub_division_description,
        p.divisions_description,
        p.customer_group_one,
        p.pnl_customer_id,
        p.customer_id,
        p.customer_name,
        p.pnl_customer_type_description,
        p.sales_group,
        p.sales_office,
        p.customer_name_level_one,
        p.customer_id_level_one,
        p.customer_name_level_two,
        p.customer_id_level_two,
        p.customer_name_level_three,
        p.customer_id_level_three,
        p.customer_name_level_four,
        p.customer_id_level_four,
        p.customer_name_level_five,
        p.customer_id_level_five,
        p.customer_group,
        p.customer_group_description,
        p.customer_type,
        p.VALUE_TYPE as PNL_VALUE_TYPE,
        p.COMPANY_CODE as PNL_COMPANY_CODE,
        p.customer_type_description,
        p.global_name,
        p.global_name_description,
        p.multinational_name,
        p.multinational_name_description,
        p.remote_system,
        sum(
            case
                when p.kpi = 'Net Sales' then coalesce(p.metric_value_usd, 0)
                else 0
            end
        ) as net_sales,
        sum(
            case
                when p.kpi = 'Gross Profit Margin' then coalesce(p.metric_value_usd, 0)
                else 0
            end
        ) as gpm,
        case
            when abs(
                sum(
                    case
                        when p.kpi = 'Net Sales' then coalesce(p.metric_value_usd, 0)
                        else 0
                    end
                )
            ) >= 1 then round(
                sum(
                    case
                        when p.kpi = 'Gross Profit Margin' then coalesce(p.metric_value_usd, 0)
                        else 0
                    end
                )::float / sum(
                    case
                        when p.kpi = 'Net Sales' then coalesce(p.metric_value_usd, 0)
                        else 0
                    end
                )::float * 100,
                4
            )
        end as gpm_pct
    from
        pnl_raw as p
    group by
        all
    having
        sum(
            case
                when p.kpi = 'Net Sales' then p.metric_value_usd
                else 0
            end
        ) != 0
        or sum(
            case
                when p.kpi = 'Gross Profit Margin' then p.metric_value_usd
                else 0
            end
        ) != 0
),
plant_units as (
    select
        cos_vol_material_id as material_id,
        cos_vol_plant as plant,
        cos_vol_posting_month as posting_month,
        sales_org_sales_organization,
        greatest(max(cos_vol_total_base_units), 0)::number(38, 4) as plant_units
    from
        SC_CON_SBX.PORTFOLIO_SIMPLIFICATION.RPT_SC_PORTFOLIO
    where
        cos_vol_posting_month >= '202501'
    group by
        cos_vol_material_id,
        cos_vol_plant,
        cos_vol_posting_month,
        sales_org_sales_organization
),
plant_share as (
    select
        material_id,
        plant,
        posting_month,
        sales_org_sales_organization,
        plant_units,
        sum(plant_units) over (
            partition by material_id,
            sales_org_sales_organization,
            posting_month
        ) as sku_units,
        count(*) over (
            partition by material_id,
            sales_org_sales_organization,
            posting_month
        ) as n_plants,
        coalesce(
            plant_units::float / nullif(
                sum(plant_units) over (
                    partition by material_id,
                    sales_org_sales_organization,
                    posting_month
                ),
                0
            )::float,
            1.0::float / count(*) over (
                partition by material_id,
                sales_org_sales_organization,
                posting_month
            )
        ) as plant_share
    from
        plant_units
),
finance_step_2 as (
    select
        sc.*,
        pnl.* exclude (
            material_id,
            calendar_year,
            calendar_month
        ),
        pnl.material_id as pnl_material_id,
        ps.plant_units,
        ps.sku_units,
        ps.n_plants,
        ps.plant_share,
        to_varchar(pnl.calendar_year) || lpad(to_varchar(pnl.calendar_month), 2, '0') as pnl_posting_month,
        case
            when sc.cos_vol_material_id is null then 'sales_only'
            when pnl.material_id is null then 'production_only'
            else 'matched'
        end as pnl_match_status,
        (pnl.net_sales * coalesce(ps.plant_share, 1.0))::number(38, 4) as adjusted_net_sales,
        (pnl.gpm * coalesce(ps.plant_share, 1.0))::number(38, 4) as adjusted_gpm,
        (
            pnl.net_sales * coalesce(ps.plant_share, 1.0)
        ) / coalesce(nullif(sc.count_of_bom_line_items, 0), 1) as split_sale_per_bom_line_item,
        (
            pnl.gpm * coalesce(ps.plant_share, 1.0)
        ) / coalesce(nullif(sc.count_of_bom_line_items, 0), 1) as split_gpm_per_bom_line_item
    from
        finance_step_1 as sc full
        outer join pnl on sc.cos_vol_material_id = pnl.material_id
        and trim(upper(pnl.sales_organization)) = trim(upper(sc.sales_org_sales_organization))
        and pnl.calendar_year = left(to_varchar(sc.cos_vol_posting_month), 4)
        and pnl.calendar_month = right(to_varchar(sc.cos_vol_posting_month), 2)
        left join plant_share as ps on sc.cos_vol_material_id = ps.material_id
        and sc.cos_vol_plant = ps.plant
        and sc.cos_vol_posting_month = ps.posting_month
        and equal_null(
            sc.sales_org_sales_organization,
            ps.sales_org_sales_organization
        )
),
abc_classification as (
    select
        distinct material as material_id,
        sales_organization,
        abc_classification,
        to_char(calendar_month_year, 'YYYYMM') as calendar_month_year
    from
        FIN_CON_SBX.PORTFOLIO_SIMPLIFICATION.RPT_ABC_CLASSIFICATION qualify row_number() over (
            partition by material,
            calendar_month_year,
            sales_organization
            order by
                net_sales desc nulls last, -- FIX #16: take the class from the region with the most sales
                abc_classification
        ) = 1
),
final_base as (
    select
        sc.cos_vol_plant as plant_id,
        sc.cos_vol_total_base_units as total_base_unit,
        sc.cos_vol_total_cases as total_cases,
        sc.cos_vol_total_pieces as total_pieces,
        sc.cos_vol_total_pallets as total_pallets,
        sc.cos_vol_total_pounds as total_pounds,
        sc.cos_vol_total_tons as total_tons,
        sc.cos_vol_total_tons_without_tb_n_id as total_tons_without_tb_n_id,
        sc.cos_vol_classifier as classifier,
        sc.cos_vol_total_qty_classifier as total_qty_classifier,
        sc.cos_vol_material_description as material_name,
        sc.cos_vol_product_hierarchy as product_hierarchy,
        sc.cos_vol_product_category as product_category,
        sc.cos_vol_product_category_description as product_category_description,
        sc.cos_vol_product_sub_category as product_sub_category,
        sc.cos_vol_product_sub_category_description as product_sub_category_description,
        sc.cos_vol_brand_equity as brand_equity,
        sc.cos_vol_brand_equity_description as brand_equity_description,
        sc.cos_vol_product_sub_brand as product_sub_brand,
        sc.cos_vol_product_sub_brand_description as product_sub_brand_description,
        sc.cos_vol_product_variant as product_variant,
        sc.cos_vol_product_variant_description as product_variant_description,
        sc.cos_vol_base_unit_of_measure as base_unit_of_measure,
        sc.cos_vol_material_type as material_type,
        sc.cos_vol_sap_system as sap_system,
        sc.material_global_material_id as global_material_id,
        sc.material_material_description as material_description,
        sc.material_material_type as material_master_type,
        sc.material_material_group as material_group,
        sc.material_division as division,
        sc.fg_material_type_description,
        sc.fg_material_group_description,
        sc.fg_gross_weight as gross_weight,
        sc.fg_net_weight as net_weight,
        sc.fg_weight_unit as weight_unit,
        sc.sales_org_life_stage as life_stage,
        sc.plant_org_city as city,
        sc.plant_org_company as company,
        sc.plant_org_company_desc as company_description,
        sc.plant_org_country as country,
        sc.plant_org_plant_classification as plant_classification,
        sc.plant_org_plant_desc as plant_description,
        sc.bom_lvl as bom_level,
        sc.bom_component,
        sc.bom_item_number, -- FIX #9: map the real BOM item number from SC (was hardcoded NULL)
        sc.bom_material_id as bom_parent_product_number,
        sc.bom_component as bom_child_product_number,
        sc.path as bom_display_path,
        sc.bom_base_qty as bom_base_quantity,
        sc.bom_component_qty,
        sc.pc_composition as bom_pc_composition,
        sc.uom as bom_component_uom,
        sc.alt_bom,
        sc.item_valid_from_date as bom_item_valid_from_date,
        sc.item_valid_to_date as bom_item_valid_to_date,
        sc.valid_from_date as bom_valid_from_date,
        sc.valid_to_date as bom_valid_to_date,
        sc.bom_component_material_group_description,
        sc.bom_component_material_group_type,
        sc.selected_alt_bom,
        sc.alt_bom_valid_from_month,
        sc.alt_bom_match_flag,
        sc.count_of_bom_line_items,
        sc.std_cost_currency as currency,
        sc.total_raw_material,
        sc.total_packaging_material,
        sc.total_conversion_cost,
        sc.std_cost_months_used,
        sc.to_currency,
        sc.conv_month as conversion_month,
        sc.conversion_rate as exchange_rate,
        sc.sold_to as pnl_customer_id,
        sc.customer_id,
        sc.customer_name,
        sc.pnl_customer_type_description as customer_type_description,
        sc.sales_group,
        sc.sales_office,
        sc.customer_name_level_one,
        sc.customer_id_level_one,
        sc.customer_name_level_two,
        sc.customer_id_level_two,
        sc.customer_name_level_three,
        sc.customer_id_level_three,
        sc.customer_name_level_four,
        sc.customer_id_level_four,
        sc.customer_name_level_five,
        sc.customer_id_level_five,
        sc.customer_group,
        sc.customer_group_description,
        sc.customer_group_one as pnl_customer_group,
        sc.PNL_COMPANY_CODE,
        sc.PNL_VALUE_TYPE,
        sc.currency as pnl_currency,
        sc.customer_type,
        sc.global_name,
        sc.global_name_description,
        sc.multinational_name,
        sc.multinational_name_description,
        sc.pnl_remote_system as pnl_source_system,
        sc.net_sales,
        sc.gpm,
        sc.gpm_pct,
        sc.plant_units,
        sc.sku_units,
        sc.n_plants,
        sc.plant_share,
        sc.adjusted_net_sales,
        sc.adjusted_gpm,
        sc.split_sale_per_bom_line_item,
        sc.split_gpm_per_bom_line_item,
        sc.pnl_match_status,
        sc.country_description,
        sc.sub_division_description,
        sc.divisions_description,
        abc.abc_classification,
        sc.average_thickness,
        sc.tube_od,
        sc.plastic_pkg_form,
        sc.tech_platform_description,
        sc.composition_name,
        coalesce(sc.cos_vol_material_id, sc.pnl_material_id) as material_id,
        coalesce(sc.cos_vol_posting_month, sc.pnl_posting_month) as posting_month,
        coalesce(
            sc.sales_org_sales_organization,
            sc.sales_organization
        ) as sales_org
    from
        finance_step_2 as sc
        left join abc_classification as abc on trim(
            upper(
                coalesce(sc.cos_vol_material_id, sc.pnl_material_id)
            )
        ) = trim(upper(abc.material_id))
        and coalesce(sc.cos_vol_posting_month, sc.pnl_posting_month) = abc.calendar_month_year
        and trim(
            upper(
                coalesce(
                    sc.sales_org_sales_organization,
                    sc.sales_organization
                )
            )
        ) = trim(upper(abc.sales_organization))
),
final as (
    select
        material_id,
        plant_id,
        posting_month,
        total_base_unit,
        total_cases,
        total_pieces,
        total_pallets,
        total_pounds,
        total_tons,
        total_tons_without_tb_n_id,
        classifier,
        total_qty_classifier,
        material_name,
        product_hierarchy,
        product_category,
        product_category_description,
        product_sub_category,
        product_sub_category_description,
        brand_equity,
        brand_equity_description,
        product_sub_brand,
        product_sub_brand_description,
        product_variant,
        product_variant_description,
        base_unit_of_measure,
        material_type,
        sap_system,
        global_material_id,
        material_description,
        material_master_type,
        material_group,
        division,
        fg_material_type_description,
        fg_material_group_description,
        gross_weight,
        net_weight,
        weight_unit,
        life_stage,
        sales_org,
        city,
        company,
        company_description,
        country,
        plant_classification,
        plant_description,
        bom_level,
        bom_component,
        bom_item_number,
        bom_parent_product_number,
        bom_child_product_number,
        bom_display_path,
        bom_base_quantity,
        bom_component_qty,
        bom_pc_composition,
        bom_component_uom,
        alt_bom,
        bom_item_valid_from_date,
        bom_item_valid_to_date,
        bom_valid_from_date,
        bom_valid_to_date,
        bom_component_material_group_description,
        bom_component_material_group_type,
        selected_alt_bom,
        alt_bom_valid_from_month,
        alt_bom_match_flag,
        count_of_bom_line_items,
        currency,
        total_raw_material,
        total_packaging_material,
        total_conversion_cost,
        std_cost_months_used,
        to_currency,
        conversion_month,
        exchange_rate,
        pnl_customer_id,
        customer_id,
        customer_name,
        customer_type_description,
        sales_group,
        sales_office,
        customer_name_level_one,
        customer_id_level_one,
        customer_name_level_two,
        customer_id_level_two,
        customer_name_level_three,
        customer_id_level_three,
        customer_name_level_four,
        customer_id_level_four,
        customer_name_level_five,
        customer_id_level_five,
        customer_group,
        customer_group_description,
        pnl_customer_group,
        PNL_COMPANY_CODE,
        PNL_VALUE_TYPE,
        pnl_currency,
        customer_type,
        global_name,
        global_name_description,
        multinational_name,
        multinational_name_description,
        pnl_source_system,
        net_sales,
        gpm,
        gpm_pct,
        plant_units,
        sku_units,
        n_plants,
        plant_share,
        adjusted_net_sales,
        adjusted_gpm,
        split_sale_per_bom_line_item,
        split_gpm_per_bom_line_item,
        pnl_match_status,
        country_description,
        sub_division_description,
        divisions_description,
        abc_classification,
        average_thickness,
        tube_od,
        plastic_pkg_form,
        tech_platform_description,
        composition_name
    from                    -- RESTORED: closing lines missing from the shared copy (see #1)
        final_base
)
select
    *
from
    final;

