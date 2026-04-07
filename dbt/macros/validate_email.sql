{% macro validate_email(column) %}
    REGEXP_LIKE({{ column }}, '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$')
{% endmacro %}
