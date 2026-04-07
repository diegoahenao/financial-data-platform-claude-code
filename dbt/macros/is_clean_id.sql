{% macro is_clean_id(column, field_name) %}
    -- Excludes two categories of garbage source IDs:
    --   1. File delimiter artifacts: "---- END OF FILE ----", "---- START OF FILE ----"
    --      These contain three or more dashes and appear when file headers/footers
    --      are accidentally ingested as data rows.
    --   2. Header rows loaded as data: the column name itself (e.g. 'customer_id')
    --      appears when SKIP_HEADER did not apply correctly on a CSV load.
    {{ column }} not ilike '%---%'
    and lower({{ column }}) != lower('{{ field_name }}')
{% endmacro %}
