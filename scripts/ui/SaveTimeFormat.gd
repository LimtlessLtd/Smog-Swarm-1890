class_name SaveTimeFormat
extends RefCounted

## Formats a save file's modification time for a browser row. One function,
## shared by SaveSlotList and CampaignBrowserView so the two lists can't
## date their entries differently.

## "2026-08-19 14:33", or "" for a missing/unknown time (0).
##
## FileAccess.get_modified_time() is a UTC Unix timestamp and
## Time.get_datetime_string_from_unix_time() converts it as UTC, so a
## straight pairing of the two shows a player in any other zone the wrong
## clock time for their own save. The bias (in minutes, east-positive) is
## added first so the string comes out in local time.
static func describe(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var local := unix_time + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	# `true` here is use_space (a " " separator instead of ISO-8601's "T"),
	# NOT the utc flag get_datetime_string_from_system() takes in that slot.
	# substr trims the seconds, which nothing about picking a save needs.
	return Time.get_datetime_string_from_unix_time(local, true).substr(0, 16)
