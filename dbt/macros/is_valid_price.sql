{% macro is_valid_price(column) %}
    ({{ column }} IS NOT NULL AND {{ column }} > 0)
{% endmacro %}
