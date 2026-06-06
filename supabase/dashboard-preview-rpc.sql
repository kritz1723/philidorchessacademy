-- ============================================================
--  Philidor Chess Academy — preview-accurate materials RPC
--  Lets an admin "View as parent" and see EXACTLY the topics that
--  parent's child sees (released + assigned), instead of the admin's
--  blanket "see everything" view.
--
--  Behaviour:
--    • parent caller            -> released + assigned to them / their child
--    • admin caller, no child   -> everything (admin browsing, unchanged)
--    • admin caller, with child -> released + assigned, evaluated as if
--                                  that child's PARENT were asking (preview)
--
--  Idempotent. Supabase -> SQL Editor -> paste -> Run.
-- ============================================================
create or replace function public.get_visible_materials(p_child uuid)
returns table (
  id                uuid,
  topic_id          uuid,
  title             text,
  description       text,
  url               text,
  storage_path      text,
  sort_order        int,
  topic_name        text,
  topic_description text,
  topic_sort        int
)
language sql security definer stable set search_path = public
as $$
  -- effective parent: admins previewing a child evaluate as that child's
  -- parent; everyone else evaluates as themselves.
  with eff as (
    select case
             when public.is_admin() and p_child is not null
               then (select c.parent_id from public.children c where c.id = p_child)
             else auth.uid()
           end as parent_id
  )
  select m.id, m.topic_id, m.title, m.description, m.url, m.storage_path, m.sort_order,
         t.name, t.description, t.sort_order
  from public.topic_materials m
  join public.topics t on t.id = m.topic_id
  cross join eff
  where
    -- admin browsing the whole library (no child context)
    (public.is_admin() and p_child is null)
    or (
      (m.is_released or (m.release_at is not null and m.release_at <= now()))
      and (
        m.assign_all
        or exists (
          select 1 from public.material_assignments a
          where a.material_id = m.id
            and ( a.parent_id = eff.parent_id
               or ( p_child is not null and a.child_id = p_child
                    and exists (select 1 from public.children c
                                where c.id = p_child and c.parent_id = eff.parent_id) ) )
        )
      )
    )
  order by t.sort_order, t.created_at, m.sort_order, m.created_at;
$$;
