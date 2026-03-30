-- Function: get_all_tags
-- Group: Tags
-- Endpoint: GET /rpc/get_all_tags
-- Doc: docs/api/tags/get_all_tags.md

create or replace function get_all_tags()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result json;
begin
    -- Fetch all tags
    select json_agg(
        json_build_object(
            'tag_id', t.tag_id,
            'tag_name', t.tag_name
        )
    )
    into v_result
    from tags t;
    -- If no data found
    if v_result is null then
        return json_build_object(
            'status', false,
            'message', 'No tags found',
            'data', '[]'::json
        );
    end if;
    -- Success response
    return json_build_object(
        'status', true,
        'message', 'Tags fetched successfully',
        'data', v_result
    );
exception
    when others then
        return json_build_object(
            'status', false,
            'message', 'Something went wrong while fetching tags',
            'error', sqlerrm
        );
end;
$$;
