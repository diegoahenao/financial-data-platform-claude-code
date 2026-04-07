{#
  Override the default generate_schema_name macro so that dbt uses the custom
  schema name directly (e.g. SILVER, GOLD) rather than appending it to the
  target schema (which would produce SILVER_SILVER, SILVER_GOLD, etc.).

  Behaviour:
    - When a model has +schema: <X> in dbt_project.yml → the model lands in <X>
    - When a model has no custom schema → it lands in target.schema
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
