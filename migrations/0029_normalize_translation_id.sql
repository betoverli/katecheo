-- Rewrite legacy YouVersion numeric translation_id values to Katecheo slug ids
-- (prefs previously stored e.g. "111" for NIV). Unknown numeric ids → nvi-pt.

update user_prefs
set translation_id = case translation_id
  when '129' then 'nvi-pt'
  when '211' then 'ntlh'
  when '1608' then 'arc'
  when '1840' then 'naa'
  when '212' then 'ara'
  when '111' then 'niv'
  when '59' then 'esv'
  when '1' then 'kjv'
  when '116' then 'nlt'
  when '114' then 'nkjv'
  when '100' then 'nasb'
  when '1713' then 'csb'
  when '206' then 'web'
  when '128' then 'rvr1960'
  when '103' then 'nvi-es'
  when '149' then 'ntv'
  else translation_id
end
where translation_id ~ '^[0-9]+$';

-- Any remaining pure-numeric ids (unknown YouVersion) fall back to nvi-pt.
update user_prefs
set translation_id = 'nvi-pt'
where translation_id ~ '^[0-9]+$';
