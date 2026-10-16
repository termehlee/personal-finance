{% macro normalize_text(column_name) -%}
    trim(regexp_replace(upper(coalesce({{ column_name }}, '')), '\s+', ' ', 'g'))
{%- endmacro %}
