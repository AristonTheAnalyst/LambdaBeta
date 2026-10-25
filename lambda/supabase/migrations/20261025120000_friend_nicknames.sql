-- A friend's nickname: the caller's own label for one friend (2026-10-25).
--
-- Nicknames exist because a friend who never filled in a name arrives in the
-- list as "Friend", and nothing else on the device can tell two such friends
-- apart — email lives in auth.users and is deliberately not synced. The
-- nickname rides the caller's OWN directed row in friend_relationship, which
-- is the only half the friends_data stream sends them, so a label never
-- reaches the friend it names.
--
-- Nullable, additive: no RLS, grant or publication change — the existing
-- owner `for all` policy already covers the new column, and the stream's
-- `SELECT *` carries it. Push this BEFORE shipping a build that writes
-- `nickname`: against an unmigrated server the upload earns PGRST204, which
-- the client retries forever — a stalled upload checkpoint, never an error
-- the user sees (same note as 20261019120000_goal_target_date.sql).
--
-- The 120-character rail is the server's backstop, deliberately far above the
-- client's 20 cap (kMaxFriendNicknameLength): the PowerSync mirror is a plain
-- Column.text with no CHECK, so an over-long write would insert locally and
-- then quarantine on upload. Same reasoning as
-- 20261020120000_name_length_rails.sql.

alter table public.friend_relationship
  add column if not exists nickname text;

alter table public.friend_relationship
  add constraint friend_relationship_nickname_length_check
  check (nickname is null or char_length(nickname) <= 120);
