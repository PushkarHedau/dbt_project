with prod_vol as (
    select
        material as material_id,
        plant,
        posting_month,
        total_base_units,
        total_cases,
        total_pieces,
        total_pallets,
        total_pounds,
        total_tons,
        total_tons_without_tb_n_id,
        classifier,
        total_qty_classifier,
        material_description,
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
        sap_system
    from SC_CON.COS_VOLUME.RPT_PRODUCTION_VOLUME
    where posting_month >= '202501'
        and UPPER(TRIM(sap_system)) != 'HUP'
        and UPPER(TRIM(plant)) not in ('HK79', 'LP70')
        and material_type in ('LSE', 'FERT', 'VERP', 'ROH', 'HALB')
),
material as (
    select
        material_description,
        material_type,
        material_group,
        division,
        remote_system,
        LTRIM(global_material_id, '0') as global_material_id,
        LTRIM(material_id, '0') as material_id
    from MD_CON.PRODUCT.RPT_MATERIAL_DENORMALIZED
    where UPPER(TRIM(remote_system)) != 'HUP'
        and material_type in ('LSE', 'FERT', 'VERP', 'ROH', 'HALB')
),
finished_goods as (
    select
        material_type,
        material_type_description,
        material_group_description,
        gross_weight,
        net_weight,
        weight_unit,
        remote_system,
        LTRIM(global_material_id, '0') as global_material_id
    from MD_CON.PRODUCT.RPT_MATERIAL_FINISHED_GOODS
),
sales_org as (
    select
        life_stage,
        material_id,
        sales_organization,
        remote_system,
        LTRIM(global_material_id, '0') as global_material_id
    from md_con.product.rpt_material_sales_organizations_denormalized
    where UPPER(TRIM(sales_organization)) not in ('HK79', 'LP70')
        and UPPER(TRIM(remote_system)) != 'HUP'
),
material_plant as (
    select
        global_material_id,
        material_id,
        plant,
        material_country_of_origin,
        spend_segment,
        spend_sub_segment,
        remote_system
    from MD_CON.PRODUCT.RPT_MATERIAL_FINISHED_GOOD_PLANTS
    where UPPER(TRIM(remote_system)) != 'HUP'
    union all
    select
        NULL as global_material_id,
        material_id,
        plant,
        material_country_of_origin,
        spend_segment,
        spend_sub_segment,
        remote_system
    from MD_CON.PRODUCT.RPT_MATERIAL_NON_FINISHED_GOOD_PLANTS
    where UPPER(TRIM(remote_system)) != 'HUP'
),
plant_org as (
    select
        city,
        company,
        company_desc,
        country,
        plant,
        plant_classification,
        plant_desc
    from SC_CON.MASTERDATA.RPT_PLANT_ORG
),
sales_org_plant_superset as (
    select
        s.material_id as sales_org_material_id,
        s.life_stage as sales_org_life_stage,
        s.remote_system as sales_org_remote_system,
        s.sales_organization as sales_org_sales_organization,
        m.global_material_id as material_plant_global_material_id,
        m.material_id as material_plant_material_id,
        m.remote_system as material_plant_remote_system,
        m.plant as material_plant_plant,
        p.city as plant_org_city,
        p.company as plant_org_company,
        p.company_desc as plant_org_company_desc,
        p.country as plant_org_country,
        p.plant as plant_org_plant,
        p.plant_classification as plant_org_plant_classification,
        p.plant_desc as plant_org_plant_desc
    from sales_org as s
        left join material_plant as m
            on TRIM(UPPER(s.material_id)) = TRIM(UPPER(m.material_id))
            and TRIM(UPPER(s.remote_system)) = TRIM(UPPER(m.remote_system))
        left join plant_org as p
            on TRIM(UPPER(m.plant)) = TRIM(UPPER(p.plant))
),
bom_master as (
    select *
    from SC_CON.INT_PORTFOLIO_MANAGEMENT.INT_SC_PORTFOLIO_MANAGEMENT_ANALYTICS_BOM_RECURSIVE_MASTER
    where COALESCE(UPPER(TRIM(item_deletion_indicator)), '') <> 'X'
),
alt_bom_validity as (
    select
        alt_bom,
        source_system,
        LTRIM(TRIM(preceeding_mtl), '0') as bom_material_id,
        TRIM(UPPER(plant_id)) as bom_plant,
        TO_CHAR(MIN(valid_from_date), 'YYYYMM') as alt_bom_valid_from_month
    from bom_master
    group by all
),
cos_vol_alt_bom as (
    select
        p.material_id,
        p.plant,
        p.posting_month,
        p.sap_system,
        p.total_base_units,
        p.total_cases,
        p.total_tons,
        v.alt_bom as selected_alt_bom,
        v.alt_bom_valid_from_month,
        case
            when v.alt_bom is NULL then 'NO_VALID_BOM'
            else 'MATCHED'
        end as alt_bom_match_flag
    from prod_vol as p
        left join alt_bom_validity as v
            on v.bom_material_id = LTRIM(TRIM(p.material_id), '0')
            and v.bom_plant = TRIM(UPPER(p.plant))
            and TRIM(UPPER(v.source_system)) = TRIM(UPPER(p.sap_system))
            and p.posting_month >= v.alt_bom_valid_from_month
    qualify ROW_NUMBER() over (
        partition by p.material_id, p.plant, p.posting_month, p.sap_system
        order by
            v.alt_bom_valid_from_month desc nulls last,
            TRY_TO_NUMBER(TO_VARCHAR(v.alt_bom)) asc nulls last,
            v.alt_bom asc
    ) = 1
),
am as (
    select
        ab.material_id,
        ab.plant,
        ab.posting_month,
        ab.sap_system,
        ab.selected_alt_bom,
        LAST_DAY(TO_DATE(TO_VARCHAR(ab.posting_month) || '01', 'YYYYMMDD')) as month_end
    from cos_vol_alt_bom as ab
    where ab.selected_alt_bom is not NULL
),
bom_candidates as (
    select
        m.*,
        am.material_id as p_material_id,
        am.plant as p_plant,
        am.posting_month as p_month,
        am.sap_system as p_sap_system,
        am.selected_alt_bom as p_selected_alt_bom,
        HASH(
            m.root_material_id,
            m.plant_id,
            m.alt_bom,
            m.path,
            m.item_number,
            m.header_change_number,
            m.item_change_number,
            m.valid_from_date,
            m.valid_to_date,
            m.item_valid_from_date,
            m.item_valid_to_date,
            m.source_system
        ) as row_key
    from am
        inner join bom_master as m
            on LTRIM(TRIM(m.root_material_id), '0') = LTRIM(TRIM(am.material_id), '0')
            and TRIM(UPPER(m.plant_id)) = TRIM(UPPER(am.plant))
            and TRIM(UPPER(m.source_system)) = TRIM(UPPER(am.sap_system))
    where am.month_end >= COALESCE(m.item_valid_from_date::DATE, '1900-01-01'::DATE)
        and am.month_end < COALESCE(m.item_valid_to_date::DATE, '9999-12-31'::DATE)
        and am.month_end >= COALESCE(m.valid_from_date::DATE, '1900-01-01'::DATE)
        and am.month_end < COALESCE(m.valid_to_date::DATE, '9999-12-31'::DATE)
),
parent_alt_selected as (
    select
        c.p_material_id,
        c.p_plant,
        c.p_month,
        c.p_sap_system,
        c.parent_material_id,
        v.alt_bom as parent_selected_alt_bom
    from (
        select distinct
            p_material_id,
            p_plant,
            p_month,
            p_sap_system,
            LTRIM(TRIM(preceeding_mtl), '0') as parent_material_id
        from bom_candidates
        where bom_lvl > 1
    ) as c
        inner join alt_bom_validity as v
            on v.bom_material_id = c.parent_material_id
            and v.bom_plant = TRIM(UPPER(c.p_plant))
            and TRIM(UPPER(v.source_system)) = TRIM(UPPER(c.p_sap_system))
            and c.p_month >= v.alt_bom_valid_from_month
    qualify ROW_NUMBER() over (
        partition by c.p_material_id, c.p_plant, c.p_month, c.p_sap_system, c.parent_material_id
        order by
            v.alt_bom_valid_from_month desc nulls last,
            TRY_TO_NUMBER(TO_VARCHAR(v.alt_bom)) asc nulls last,
            v.alt_bom asc
    ) = 1
),
bom_in_month as (
    select c.*
    from bom_candidates as c
        left join parent_alt_selected as s
            on c.p_material_id = s.p_material_id
            and c.p_plant = s.p_plant
            and c.p_month = s.p_month
            and c.p_sap_system = s.p_sap_system
            and LTRIM(TRIM(c.preceeding_mtl), '0') = s.parent_material_id
    where (c.bom_lvl = 1 and TRIM(UPPER(c.alt_bom)) = TRIM(UPPER(c.p_selected_alt_bom)))
        or (c.bom_lvl > 1 and TRIM(UPPER(c.alt_bom)) = TRIM(UPPER(s.parent_selected_alt_bom)))
),
bom_path_valid as (
    select
        r.p_material_id,
        r.p_plant,
        r.p_month,
        r.p_sap_system,
        r.row_key,
        r.bom_lvl,
        r.COMPONENT_MATERIAL_GROUP_TYPE
    from bom_in_month as r
        left join bom_in_month as a
            on r.p_material_id = a.p_material_id
            and r.p_plant = a.p_plant
            and r.p_month = a.p_month
            and r.p_sap_system = a.p_sap_system
            and STARTSWITH(r.path, a.path || '>') -- FIX B1: delimiter is '>' with no spaces
    where r.component_material_description is not NULL
        and r.COMPONENT_MATERIAL_GROUP_TYPE is not NULL
    group by
        r.p_material_id,
        r.p_plant,
        r.p_month,
        r.p_sap_system,
        r.row_key,
        r.bom_lvl,
        r.path,
        r.item_number,
        r.valid_from_date,
        r.item_valid_from_date,
        r.item_change_number,
        r.COMPONENT_MATERIAL_GROUP_TYPE
    having COUNT(distinct a.path) = r.bom_lvl - 1
    qualify ROW_NUMBER() over (
        partition by r.p_material_id, r.p_plant, r.p_month, r.p_sap_system, r.path, r.item_number
        order by
            r.valid_from_date desc,
            r.item_valid_from_date desc,
            r.item_change_number desc nulls last
    ) = 1
),
bom_formula_filtered as (
    select
        p_material_id,
        p_plant,
        p_month,
        p_sap_system,
        row_key
    from bom_path_valid
    qualify COMPONENT_MATERIAL_GROUP_TYPE <> 'FORMULA'
        or bom_lvl = MIN(case when COMPONENT_MATERIAL_GROUP_TYPE = 'FORMULA' then bom_lvl end) over (
            partition by p_material_id, p_plant, p_month, p_sap_system
        )
),
bom_final as (
    select
        b.preceeding_mtl as bom_material_id,
        b.root_material_id,
        b.alt_bom,
        b.bom_component,
        b.item_number as bom_item_number,
        parent_material_type as bom_material_type,
        b.component_material_type as bom_component_material_type,
        b.component_material_description as bom_component_material_description,
        b.item_change_number,
        b.valid_from_date,
        b.valid_to_date,
        b.item_valid_from_date,
        b.item_valid_to_date,
        b.bom_lvl,
        b.path,
        b.plant_id as bom_plant,
        b.COMPONENT_MATERIAL_GROUP_TYPE as bom_component_material_group_type,
        HASH(
            b.root_material_id,
            b.plant_id,
            b.alt_bom,
            b.path,
            b.item_number,
            b.header_change_number,
            b.item_change_number,
            b.valid_from_date,
            b.valid_to_date,
            b.item_valid_from_date,
            b.item_valid_to_date,
            b.source_system
        ) as row_key
    from bom_master as b
    where b.component_material_description is not NULL
        and b.COMPONENT_MATERIAL_GROUP_TYPE is not NULL
),
packaging as (
    select
        material_number,
        MAX(case when UPPER(TRIM(characteristics_name)) = 'AVERAGE_THICKNESS' then characteristics_value end) as average_thickness,
        MAX(case when UPPER(TRIM(characteristics_name)) = 'MATERIAL_TYPE' then characteristics_value end) as material_type,
        MAX(case when UPPER(TRIM(characteristics_name)) = 'TUBE_OD' then characteristics_value end) as tube_od,
        MAX(case when UPPER(TRIM(characteristics_name)) = 'PLASTIC_PKG_FORM' then characteristics_value end) as plastic_pkg_form
    from GTECH_CUR.PACKAGING.DIM_SAP_PACK
    group by material_number
),
tech_platform as (
    select
        LTRIM(TRIM(bnumber), '0') as bnumber_key,
        TRIM(tech_platform_description) as tech_platform_description,
        TRIM(composition_name) as composition_name,
        TRIM(change_number) as change_number,
        TRIM(tech_platform_id) as tech_platform_id,
        COALESCE(bnumber_bom_valid_from_date::DATE, '1900-01-01'::DATE) as tp_valid_from,
        COALESCE(bnumber_bom_valid_to_date::DATE, '9999-12-31'::DATE) as tp_valid_to
    from GTECH_CON_SBX.TECH_PLATFORM.RPT_PMA_TECH_PLATFORM
    where NULLIF(TRIM(bnumber), '') is not NULL
        and NULLIF(TRIM(tech_platform_description), '') is not NULL
),
formula_months as (
    select distinct
        LTRIM(TRIM(b.bom_component), '0') as bnumber_key,
        v.p_month,
        LAST_DAY(TO_DATE(TO_VARCHAR(v.p_month) || '01', 'YYYYMMDD')) as month_end
    from bom_formula_filtered as v
        inner join bom_final as b on v.row_key = b.row_key
    where b.bom_component_material_group_type = 'FORMULA'
),
tech_platform_month as (
    select
        fm.bnumber_key,
        fm.p_month,
        tp.tech_platform_description,
        tp.composition_name
    from formula_months as fm
        inner join tech_platform as tp
            on tp.bnumber_key = fm.bnumber_key
            and fm.month_end >= tp.tp_valid_from
            and fm.month_end < tp.tp_valid_to
    qualify ROW_NUMBER() over (
        partition by fm.bnumber_key, fm.p_month
        order by
            TRY_TO_NUMBER(tp.change_number) asc nulls last,
            tp.change_number asc nulls last,
            tp.tech_platform_id asc
    ) = 1
),
final as (
    select
        p.material_id as cos_vol_material_id,
        p.plant as cos_vol_plant,
        p.posting_month as cos_vol_posting_month,
        p.total_base_units as cos_vol_total_base_units,
        p.total_cases as cos_vol_total_cases,
        p.total_pieces as cos_vol_total_pieces,
        p.total_pallets as cos_vol_total_pallets,
        p.total_pounds as cos_vol_total_pounds,
        p.total_tons as cos_vol_total_tons,
        p.total_tons_without_tb_n_id as cos_vol_total_tons_without_tb_n_id,
        p.classifier as cos_vol_classifier,
        p.total_qty_classifier as cos_vol_total_qty_classifier,
        p.material_description as cos_vol_material_description,
        p.product_hierarchy as cos_vol_product_hierarchy,
        p.product_category as cos_vol_product_category,
        p.product_category_description as cos_vol_product_category_description,
        p.product_sub_category as cos_vol_product_sub_category,
        p.product_sub_category_description as cos_vol_product_sub_category_description,
        p.brand_equity as cos_vol_brand_equity,
        p.brand_equity_description as cos_vol_brand_equity_description,
        p.product_sub_brand as cos_vol_product_sub_brand,
        p.product_sub_brand_description as cos_vol_product_sub_brand_description,
        p.product_variant as cos_vol_product_variant,
        p.product_variant_description as cos_vol_product_variant_description,
        p.base_unit_of_measure as cos_vol_base_unit_of_measure,
        p.material_type as cos_vol_material_type,
        p.sap_system as cos_vol_sap_system,
        m.global_material_id as material_global_material_id,
        m.material_id as material_material_id,
        m.material_description as material_material_description,
        m.material_type as material_material_type,
        m.material_group as material_material_group,
        m.division as material_division,
        m.remote_system as material_remote_system,
        f.global_material_id as fg_global_material_id,
        f.material_type as fg_material_type,
        f.material_type_description as fg_material_type_description,
        f.material_group_description as fg_material_group_description,
        f.gross_weight as fg_gross_weight,
        f.net_weight as fg_net_weight,
        f.weight_unit as fg_weight_unit,
        a.sales_org_material_id,
        a.sales_org_life_stage,
        a.sales_org_remote_system,
        a.sales_org_sales_organization,
        a.material_plant_global_material_id,
        a.material_plant_material_id,
        a.material_plant_remote_system,
        po.city as plant_org_city, -- FIX #7a: plant attributes joined directly on production plant
        po.company as plant_org_company,
        po.company_desc as plant_org_company_desc,
        po.country as plant_org_country,
        po.plant as plant_org_plant,
        po.plant_classification as plant_org_plant_classification,
        po.plant_desc as plant_org_plant_desc,
        ab.selected_alt_bom,
        ab.alt_bom_valid_from_month,
        ab.alt_bom_match_flag,
        b.bom_material_id,
        b.alt_bom,
        b.bom_component,
        b.bom_component_material_type,
        b.bom_component_material_description,
        b.bom_item_number,
        b.item_change_number,
        b.item_valid_from_date,
        b.item_valid_to_date,
        b.valid_from_date,
        b.valid_to_date,
        b.bom_lvl,
        b.bom_material_type,
        b.path,
        NULL as pc_composition,
        b.bom_plant,
        b.bom_component_material_group_type,
        pg.average_thickness,
        pg.material_type as packaging_material_type,
        pg.tube_od,
        pg.plastic_pkg_form,
        tp.tech_platform_description,
        tp.composition_name
    from prod_vol as p
        left join material as m
            on TRIM(UPPER(p.material_id)) = TRIM(UPPER(m.material_id))
            and TRIM(UPPER(p.sap_system)) = TRIM(UPPER(m.remote_system))
        left join finished_goods as f
            on TRIM(UPPER(m.global_material_id)) = TRIM(UPPER(f.global_material_id))
        left join sales_org_plant_superset as a
            on TRIM(UPPER(p.material_id)) = TRIM(UPPER(a.sales_org_material_id))
            and TRIM(UPPER(p.plant)) = TRIM(UPPER(a.material_plant_plant))
            and TRIM(UPPER(p.sap_system)) = TRIM(UPPER(a.sales_org_remote_system))
        left join plant_org as po
            on TRIM(UPPER(p.plant)) = TRIM(UPPER(po.plant)) -- FIX #7a: plant_org is one row per plant
        left join cos_vol_alt_bom as ab
            on TRIM(UPPER(p.material_id)) = TRIM(UPPER(ab.material_id))
            and TRIM(UPPER(p.plant)) = TRIM(UPPER(ab.plant))
            and p.posting_month = ab.posting_month
            and TRIM(UPPER(p.sap_system)) = TRIM(UPPER(ab.sap_system))
        left join bom_formula_filtered as v
            on p.material_id = v.p_material_id
            and p.plant = v.p_plant
            and p.posting_month = v.p_month
            and TRIM(UPPER(p.sap_system)) = TRIM(UPPER(v.p_sap_system))
        left join bom_final as b
            on v.row_key = b.row_key
        left join packaging as pg
            on LTRIM(TRIM(pg.material_number), '0') = LTRIM(TRIM(b.bom_component), '0')
        left join tech_platform_month as tp -- FIX TP1: matched on BNUMBER and posting month
            on tp.bnumber_key = LTRIM(TRIM(b.bom_component), '0')
            and tp.p_month = p.posting_month
            and b.bom_component_material_group_type = 'FORMULA'
    qualify ROW_NUMBER() over (
        partition by
            p.material_id,
            p.plant,
            p.posting_month,
            p.total_base_units,
            p.total_cases,
            p.total_pieces,
            p.total_pallets,
            p.total_pounds,
            p.total_tons,
            p.total_tons_without_tb_n_id,
            p.classifier,
            p.total_qty_classifier,
            p.material_description,
            p.product_hierarchy,
            p.product_category,
            p.product_category_description,
            p.product_sub_category,
            p.product_sub_category_description,
            p.brand_equity,
            p.brand_equity_description,
            p.product_sub_brand,
            p.product_sub_brand_description,
            p.product_variant,
            p.product_variant_description,
            p.base_unit_of_measure,
            p.material_type,
            p.sap_system,
            m.global_material_id,
            m.material_id,
            m.material_description,
            m.material_type,
            m.material_group,
            m.division,
            m.remote_system,
            f.global_material_id,
            f.material_type,
            f.material_type_description,
            f.material_group_description,
            f.gross_weight,
            f.net_weight,
            f.weight_unit,
            a.sales_org_material_id,
            a.sales_org_life_stage,
            a.sales_org_remote_system,
            a.sales_org_sales_organization,
            a.material_plant_global_material_id,
            a.material_plant_material_id,
            a.material_plant_remote_system,
            a.material_plant_plant,
            po.city,
            po.company,
            po.company_desc,
            po.country,
            po.plant,
            po.plant_classification,
            po.plant_desc,
            ab.selected_alt_bom,
            ab.alt_bom_valid_from_month,
            ab.alt_bom_match_flag,
            b.bom_material_id,
            b.alt_bom,
            b.bom_component,
            b.bom_item_number,
            b.bom_component_material_type,
            b.bom_component_material_description,
            b.item_change_number,
            b.valid_from_date,
            b.valid_to_date,
            b.item_valid_from_date,
            b.item_valid_to_date,
            b.bom_lvl,
            b.bom_material_type,
            b.path,
            b.bom_plant,
            b.bom_component_material_group_type
        order by b.bom_lvl
    ) = 1
)
select
    final.*,
    COUNT(bom_component) over (
        partition by cos_vol_material_id, cos_vol_plant, cos_vol_posting_month, sales_org_sales_organization
    ) as count_of_bom_line_items
from final