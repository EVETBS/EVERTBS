class_name UpdateConfig
extends RefCounted

## Frozen shell protocol id — must match version.json.shellCompatibilityId
const SHELL_COMPATIBILITY_ID := "evertbs-shell-v1"
const PROTOCOL_SUPPORTED := 1

const VERSION_FILE := "version.json"
const MANIFEST_FILE := "manifest.json"
const APPLIED_VERSION_FILE := "applied_version.json"
const ONLINE_UPDATE_DIR := "user://online_update"
const CONTENT_RUNTIME_DIR := "user://content_runtime"
const BOOTSTRAP_OVERRIDE_FILE := "user://bootstrap_override.json"

## HF bucket resolve (authoritative). Order = try order.
const DEFAULT_BASE_URLS: PackedStringArray = [
	"https://huggingface.co/buckets/liketocode789/EVERTBS/resolve/",
]

const GITHUB_POINTER_VERSION_URL := (
	"https://evetbs.github.io/EVERTBS-online-update/version.json"
)

const DEFAULT_ENTRY := "res://game/main_menu.tscn"

static var base_url: String = DEFAULT_BASE_URLS[0]


static func get_platform_id() -> String:
	var name := OS.get_name()
	match name:
		"Windows", "UWP":
			return "windows"
		"Android":
			return "android"
		_:
			# Editor / unexpected: treat as windows for local serve testing
			return "windows"


static func apply_remote_base_url(remote: String) -> void:
	var t := remote.strip_edges()
	if t.is_empty():
		return
	if not t.ends_with("/"):
		t += "/"
	base_url = t


static func combine(root: String, rel: String) -> String:
	var r := root.strip_edges()
	if not r.ends_with("/"):
		r += "/"
	var p := rel.strip_edges()
	while p.begins_with("/"):
		p = p.substr(1)
	return r + p


static func version_url() -> String:
	return combine(base_url, VERSION_FILE)


static func manifest_url() -> String:
	return combine(base_url, MANIFEST_FILE)


static func file_url(rel_path: String) -> String:
	return combine(base_url, rel_path)


static func _read_bootstrap_override() -> Dictionary:
	if not FileAccess.file_exists(BOOTSTRAP_OVERRIDE_FILE):
		return {}
	var f := FileAccess.open(BOOTSTRAP_OVERRIDE_FILE, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


static func lock_base_url_from_override() -> bool:
	## When true, ignore version.json baseUrl (local CDN / LAN debug).
	var d := _read_bootstrap_override()
	return bool(d.get("lockBaseUrl", false))


static func load_bootstrap_override_base_urls() -> PackedStringArray:
	var out: PackedStringArray = []
	var d := _read_bootstrap_override()
	if d.is_empty():
		return out
	if d.has("baseUrl") and typeof(d["baseUrl"]) == TYPE_STRING:
		out.append(str(d["baseUrl"]))
	if d.has("baseUrls") and typeof(d["baseUrls"]) == TYPE_ARRAY:
		for item in d["baseUrls"]:
			out.append(str(item))
	return out


static func candidate_base_urls() -> PackedStringArray:
	var urls: PackedStringArray = []
	for u in load_bootstrap_override_base_urls():
		urls.append(u)
	for u in DEFAULT_BASE_URLS:
		urls.append(u)
	return urls


static func is_manifest_path_wanted(path: String, platform_id: String) -> bool:
	var p := path.replace("\\", "/")
	if p.begins_with("platform/"):
		var rest := p.substr("platform/".length())
		var slash := rest.find("/")
		var plat := rest if slash < 0 else rest.substr(0, slash)
		return plat == platform_id
	return true


static func ensure_dirs() -> void:
	# Android needs absolute filesystem paths for make_dir_recursive_absolute.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ONLINE_UPDATE_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT_RUNTIME_DIR))
	## D-EAC-34 semi-expose root (DataStore seeds JSON here on first load).
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT_RUNTIME_DIR.path_join("data")))


static func applied_version_path() -> String:
	return ONLINE_UPDATE_DIR.path_join(APPLIED_VERSION_FILE)


static func runtime_file_path(rel: String) -> String:
	return CONTENT_RUNTIME_DIR.path_join(rel.replace("\\", "/"))
