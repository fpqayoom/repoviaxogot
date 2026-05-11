@tool
extends Control

# ── Constants ─────────────────────────────────────────────────────────────────
const SAVE_PATH := "user://qugit_auth.cfg"
const IGNORE_EXTENSIONS := [".uid", ".import", ".godot", ".tmp", ".bak"]
const IGNORE_NAMES := [".git", ".DS_Store", "Thumbs.db"]
const IGNORE_DIRS := [".git", ".godot"]

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var _api: Node = $API

@onready var _token_in: LineEdit        = %TokenInput
@onready var _connect_btn: Button       = %ConnectBtn
@onready var _status_lbl: Label         = %StatusLabel
@onready var _rate_lbl: Label           = %RateLabel
@onready var _tabs: TabContainer        = %Tabs

# Repos tab
@onready var _repo_search: LineEdit     = %RepoSearch
@onready var _repo_search_btn: Button   = %RepoSearchBtn
@onready var _repo_list: ItemList       = %RepoList
@onready var _repo_detail: RichTextLabel = %RepoDetail
@onready var _repo_prev: Button         = %RepoPrev
@onready var _repo_next: Button         = %RepoNext
@onready var _repo_page_lbl: Label      = %RepoPageLbl
@onready var _new_repo_name: LineEdit   = %NewRepoName
@onready var _new_repo_desc: LineEdit   = %NewRepoDesc
@onready var _new_repo_priv: CheckBox   = %NewRepoPriv
@onready var _new_repo_btn: Button      = %NewRepoBtn

# Branch tab
@onready var _br_repo_pick: OptionButton = %BrRepoPick
@onready var _br_owner: LineEdit        = %BrOwner
@onready var _br_repo: LineEdit         = %BrRepo
@onready var _br_fetch_btn: Button      = %BrFetchBtn
@onready var _br_list: ItemList         = %BrList
@onready var _br_new_name: LineEdit     = %BrNewName
@onready var _br_from: OptionButton     = %BrFrom
@onready var _br_create_btn: Button     = %BrCreateBtn
@onready var _br_delete_btn: Button     = %BrDeleteBtn
@onready var _merge_base: OptionButton  = %MergeBase
@onready var _merge_head: OptionButton  = %MergeHead
@onready var _merge_msg: LineEdit       = %MergeMsg
@onready var _merge_btn: Button         = %MergeBtn

# Files tab
@onready var _file_repo_pick: OptionButton = %FileRepoPick
@onready var _file_owner: LineEdit      = %FileOwner
@onready var _file_repo: LineEdit       = %FileRepo
@onready var _file_branch: OptionButton = %FileBranch
@onready var _file_load_btn: Button     = %FileLoadBtn
@onready var _file_tree: ItemList       = %FileTree
@onready var _file_content: CodeEdit    = %FileContent
@onready var _file_path_lbl: Label      = %FilePathLbl
@onready var _push_msg: LineEdit        = %PushMsg
@onready var _push_btn: Button          = %PushBtn
@onready var _pull_btn: Button          = %PullBtn
@onready var _local_path: LineEdit      = %LocalPath
@onready var _scan_btn: Button          = %ScanBtn
@onready var _push_multi_btn: Button    = %PushMultiBtn
@onready var _push_sel_btn: Button      = %PushSelBtn
@onready var _ignore_lbl: Label         = %IgnoreLbl

# Commits tab
@onready var _cm_repo_pick: OptionButton = %CmRepoPick
@onready var _cm_owner: LineEdit        = %CmOwner
@onready var _cm_repo: LineEdit         = %CmRepo
@onready var _cm_branch: LineEdit       = %CmBranch
@onready var _cm_fetch_btn: Button      = %CmFetchBtn
@onready var _cm_list: ItemList         = %CmList
@onready var _cm_prev: Button           = %CmPrev
@onready var _cm_next: Button           = %CmNext
@onready var _cm_detail: RichTextLabel  = %CmDetail
@onready var _diff_view: CodeEdit       = %DiffView

# PRs tab
@onready var _pr_repo_pick: OptionButton = %PrRepoPick
@onready var _pr_owner: LineEdit        = %PrOwner
@onready var _pr_repo: LineEdit         = %PrRepo
@onready var _pr_state_opt: OptionButton = %PrStateOpt
@onready var _pr_fetch_btn: Button      = %PrFetchBtn
@onready var _pr_list: ItemList         = %PrList
@onready var _pr_detail: RichTextLabel  = %PrDetail
@onready var _pr_merge_btn: Button      = %PrMergeBtn
@onready var _pr_close_btn: Button      = %PrCloseBtn
@onready var _pr_title: LineEdit        = %PrTitle
@onready var _pr_body: TextEdit         = %PrBody
@onready var _pr_head: LineEdit         = %PrHead
@onready var _pr_base: LineEdit         = %PrBase
@onready var _pr_create_btn: Button     = %PrCreateBtn

# Issues tab
@onready var _is_repo_pick: OptionButton = %IsRepoPick
@onready var _is_owner: LineEdit        = %IsOwner
@onready var _is_repo: LineEdit         = %IsRepo
@onready var _is_state_opt: OptionButton = %IsStateOpt
@onready var _is_fetch_btn: Button      = %IsFetchBtn
@onready var _is_list: ItemList         = %IsList
@onready var _is_detail: RichTextLabel  = %IsDetail
@onready var _is_close_btn: Button      = %IsCloseBtn
@onready var _is_title: LineEdit        = %IsTitle
@onready var _is_body: TextEdit         = %IsBody
@onready var _is_create_btn: Button     = %IsCreateBtn

# ── State ─────────────────────────────────────────────────────────────────────
var _repos: Array = []
var _repos_page := 1
var _repos_search_mode := false

var _branches: Array = []

var _tree_files: Array = []          # items shown in FileTree list
var _current_file_sha := ""
var _current_file_path := ""
var _current_file_branch := ""
var _local_changed_files: Array = [] # relative paths after scan

var _commits: Array = []
var _commits_page := 1

var _pulls: Array = []
var _selected_pr_number := -1

var _issues: Array = []
var _selected_issue_number := -1

var _ctx_owner := ""
var _ctx_repo := ""
var _ctx_branch := ""

var _pending_push: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_api.request_completed.connect(_on_done_patched)
	_api.request_failed.connect(_on_fail)
	_api.rate_limit_updated.connect(func(r): _rate_lbl.text = "API: %d left" % r)

	_connect_btn.pressed.connect(_do_connect)
	_token_in.text_submitted.connect(func(_t): _do_connect())

	# Repos tab
	_repo_search_btn.pressed.connect(_repo_search_go)
	_repo_search.text_submitted.connect(func(_t): _repo_search_go())
	_repo_list.item_selected.connect(_on_repo_selected)
	_repo_prev.pressed.connect(func(): _repos_page = max(1, _repos_page-1); _repo_load_page())
	_repo_next.pressed.connect(func(): _repos_page += 1; _repo_load_page())
	_new_repo_btn.pressed.connect(_do_create_repo)

	# Repo pickers in each tab
	_br_repo_pick.item_selected.connect(func(i): _pick_repo_for(i, _br_owner, _br_repo))
	_file_repo_pick.item_selected.connect(func(i): _pick_repo_for(i, _file_owner, _file_repo))
	_cm_repo_pick.item_selected.connect(func(i): _pick_repo_for(i, _cm_owner, _cm_repo))
	_pr_repo_pick.item_selected.connect(func(i): _pick_repo_for(i, _pr_owner, _pr_repo))
	_is_repo_pick.item_selected.connect(func(i): _pick_repo_for(i, _is_owner, _is_repo))

	# Branch tab
	_br_fetch_btn.pressed.connect(_br_fetch)
	_br_create_btn.pressed.connect(_br_create)
	_br_delete_btn.pressed.connect(_br_delete)
	_merge_btn.pressed.connect(_do_merge)

	# Files tab
	_file_load_btn.pressed.connect(_file_load_tree)
	_file_tree.item_selected.connect(_on_file_selected)
	_push_btn.pressed.connect(_do_push_file)
	_pull_btn.pressed.connect(_do_pull_file)
	_scan_btn.pressed.connect(_scan_local)
	_push_multi_btn.pressed.connect(_do_push_multi)
	_push_sel_btn.pressed.connect(_do_push_selected)
	_file_tree.select_mode = ItemList.SELECT_MULTI

	# Commits tab
	_cm_fetch_btn.pressed.connect(_cm_fetch)
	_cm_list.item_selected.connect(_on_commit_selected)
	_cm_prev.pressed.connect(func(): _commits_page = max(1, _commits_page-1); _cm_fetch())
	_cm_next.pressed.connect(func(): _commits_page += 1; _cm_fetch())

	# PRs tab
	_pr_fetch_btn.pressed.connect(_pr_fetch)
	_pr_list.item_selected.connect(_on_pr_selected)
	_pr_merge_btn.pressed.connect(_do_pr_merge)
	_pr_close_btn.pressed.connect(_do_pr_close)
	_pr_create_btn.pressed.connect(_do_pr_create)

	# Issues tab
	_is_fetch_btn.pressed.connect(_is_fetch)
	_is_list.item_selected.connect(_on_issue_selected)
	_is_close_btn.pressed.connect(_do_issue_close)
	_is_create_btn.pressed.connect(_do_issue_create)

	_load_saved_token()

# ── Token persistence ─────────────────────────────────────────────────────────

func _load_saved_token() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var tok: String = cfg.get_value("auth", "token", "")
		if tok != "":
			_token_in.text = tok
			_api.set_token(tok)
			_set_status("Saved token found — connecting…", false)
			_api.fetch_user()
			return
	_set_status("Enter token and click Connect", false)

func _save_token(tok: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", tok)
	cfg.save(SAVE_PATH)

# ── Auth ──────────────────────────────────────────────────────────────────────

func _do_connect() -> void:
	var tok := _token_in.text.strip_edges()
	if tok == "":
		_set_status("Token is empty", true)
		return
	_api.set_token(tok)
	_set_status("Verifying token…", false)
	_api.fetch_user()

# ── Repo tab ──────────────────────────────────────────────────────────────────

func _repo_search_go() -> void:
	var q := _repo_search.text.strip_edges()
	_repos_page = 1
	if q == "":
		_repos_search_mode = false
		_api.fetch_my_repos(1)
	else:
		_repos_search_mode = true
		_api.search_repos(q, 1)
	_set_status("Loading repos…", false)

func _repo_load_page() -> void:
	if _repos_search_mode:
		_api.search_repos(_repo_search.text.strip_edges(), _repos_page)
	else:
		_api.fetch_my_repos(_repos_page)

func _populate_repos(data: Array) -> void:
	_repos = data
	_repo_list.clear()
	# Refresh all tab repo pickers
	for pick in [_br_repo_pick, _file_repo_pick, _cm_repo_pick, _pr_repo_pick, _is_repo_pick]:
		pick.clear()
		pick.add_item("— pick repo —")
	for r in data:
		if not r is Dictionary: continue
		var full: String = r.get("full_name", "?")
		var s := "%s  ★%d" % [full, r.get("stargazers_count", 0)]
		var lang: String = r.get("language", "") if r.get("language") != null else ""
		if lang != "": s += "  [%s]" % lang
		_repo_list.add_item(s)
		for pick in [_br_repo_pick, _file_repo_pick, _cm_repo_pick, _pr_repo_pick, _is_repo_pick]:
			pick.add_item(full)
	_repo_page_lbl.text = "Page %d" % _repos_page
	_repo_prev.disabled = _repos_page <= 1

func _on_repo_selected(idx: int) -> void:
	if idx < 0 or idx >= _repos.size(): return
	var r: Dictionary = _repos[idx]
	_ctx_owner = r.get("owner", {}).get("login", "")
	_ctx_repo  = r.get("name", "")
	_ctx_branch = r.get("default_branch", "main")
	_fill_repo_detail(r)
	_autofill_all()

func _fill_repo_detail(r: Dictionary) -> void:
	var desc: String = r.get("description", "") if r.get("description") != null else ""
	var txt := "[b]%s[/b]\n%s\n\n" % [r.get("full_name",""), desc]
	txt += "★%d  🍴%d  👁%d\n" % [r.get("stargazers_count",0), r.get("forks_count",0), r.get("watchers_count",0)]
	txt += "Lang: %s  |  Branch: %s  |  Issues: %d\n" % [
		r.get("language","N/A") if r.get("language") != null else "N/A",
		r.get("default_branch","main"), r.get("open_issues_count",0)]
	txt += "Private: %s\n" % ("Yes" if r.get("private",false) else "No")
	var pushed: String = r.get("pushed_at","") if r.get("pushed_at") != null else ""
	if pushed.length() >= 10: txt += "Last push: %s\n" % pushed.substr(0,10)
	txt += "\n[url]%s[/url]" % r.get("html_url","")
	_repo_detail.text = txt

func _autofill_all() -> void:
	for n in [_br_owner, _file_owner, _cm_owner, _pr_owner, _is_owner]:
		if n: n.text = _ctx_owner
	for n in [_br_repo, _file_repo, _cm_repo, _pr_repo, _is_repo]:
		if n: n.text = _ctx_repo
	if _cm_branch: _cm_branch.text = _ctx_branch
	# Sync pickers to selected repo
	for pick in [_br_repo_pick, _file_repo_pick, _cm_repo_pick, _pr_repo_pick, _is_repo_pick]:
		for i in pick.item_count:
			if pick.get_item_text(i) == _ctx_owner + "/" + _ctx_repo:
				pick.select(i)
				break

func _pick_repo_for(idx: int, owner_node: LineEdit, repo_node: LineEdit) -> void:
	# idx 0 = placeholder, so real repos start at 1
	var real := idx - 1
	if real < 0 or real >= _repos.size(): return
	var r: Dictionary = _repos[real]
	owner_node.text = r.get("owner", {}).get("login", "")
	repo_node.text  = r.get("name", "")

func _do_create_repo() -> void:
	var name := _new_repo_name.text.strip_edges()
	if name == "":
		_set_status("Repo name required", true)
		return
	_api.create_repo(name, _new_repo_desc.text.strip_edges(), _new_repo_priv.button_pressed)
	_set_status("Creating repo…", false)

# ── Branch tab ────────────────────────────────────────────────────────────────

func _br_fetch() -> void:
	var o := _br_owner.text.strip_edges()
	var r := _br_repo.text.strip_edges()
	if o == "" or r == "": _set_status("Owner+repo required", true); return
	_set_status("Loading branches…", false)
	_api.fetch_branches(o, r)

func _populate_branches(data: Array) -> void:
	_branches = data
	_br_list.clear()
	_br_from.clear()
	_merge_base.clear()
	_merge_head.clear()
	_file_branch.clear()
	for b in data:
		if not b is Dictionary: continue
		var name: String = b.get("name","")
		_br_list.add_item(name)
		_br_from.add_item(name)
		_merge_base.add_item(name)
		_merge_head.add_item(name)
		_file_branch.add_item(name)
	for i in _branches.size():
		var b: Dictionary = _branches[i]
		if b.get("name","") == _ctx_branch:
			_br_from.select(i)
			_file_branch.select(i)
			break

func _br_create() -> void:
	var name := _br_new_name.text.strip_edges()
	if name == "": _set_status("Branch name required", true); return
	var idx := _br_from.selected
	if idx < 0 or idx >= _branches.size(): _set_status("Select source branch", true); return
	var sha: String = _branches[idx].get("commit",{}).get("sha","")
	if sha == "": _set_status("Could not get source SHA", true); return
	_api.create_branch(_br_owner.text.strip_edges(), _br_repo.text.strip_edges(), name, sha)
	_set_status("Creating branch…", false)

func _br_delete() -> void:
	var sel := _br_list.get_selected_items()
	if sel.is_empty(): _set_status("Select a branch to delete", true); return
	var name: String = _branches[sel[0]].get("name","")
	_api.delete_branch(_br_owner.text.strip_edges(), _br_repo.text.strip_edges(), name)
	_set_status("Deleting branch…", false)

func _do_merge() -> void:
	var base_idx := _merge_base.selected
	var head_idx := _merge_head.selected
	if base_idx < 0 or head_idx < 0: _set_status("Select base and head branches", true); return
	var base: String = _branches[base_idx].get("name","")
	var head: String = _branches[head_idx].get("name","")
	var msg := _merge_msg.text.strip_edges()
	if msg == "": msg = "Merge %s into %s" % [head, base]
	_api.merge_branches(_br_owner.text.strip_edges(), _br_repo.text.strip_edges(), base, head, msg)
	_set_status("Merging…", false)

# ── Files tab ─────────────────────────────────────────────────────────────────

func _is_ignored(path: String) -> bool:
	var fname := path.get_file()
	for ig in IGNORE_NAMES:
		if fname == ig: return true
	var ext := "." + path.get_extension()
	for ig in IGNORE_EXTENSIONS:
		if ext == ig: return true
	for seg in path.split("/"):
		for ig in IGNORE_DIRS:
			if seg == ig: return true
	return false

func _file_load_tree() -> void:
	var o := _file_owner.text.strip_edges()
	var r := _file_repo.text.strip_edges()
	if o == "" or r == "": _set_status("Owner+repo required", true); return
	var br := _file_branch.get_item_text(_file_branch.selected) if _file_branch.selected >= 0 else "HEAD"
	_ctx_branch = br
	_set_status("Loading file tree…", false)
	_api.fetch_tree(o, r, br)

func _populate_tree(data: Dictionary) -> void:
	_tree_files = []
	_file_tree.clear()
	var items: Array = data.get("tree", [])
	for item in items:
		if not item is Dictionary: continue
		if item.get("type","") != "blob": continue
		var path: String = item.get("path","")
		if _is_ignored(path): continue
		_tree_files.append(item)
		_file_tree.add_item(path)

func _on_file_selected(idx: int) -> void:
	if idx < 0 or idx >= _tree_files.size(): return
	var item: Dictionary = _tree_files[idx]
	_current_file_path = item.get("path","")
	_current_file_branch = _ctx_branch
	_file_path_lbl.text = _current_file_path
	_file_content.text = "Loading…"
	_api.fetch_file_meta(_file_owner.text.strip_edges(), _file_repo.text.strip_edges(),
		_current_file_path, _current_file_branch)

func _do_push_file() -> void:
	var o := _file_owner.text.strip_edges()
	var r := _file_repo.text.strip_edges()
	var path := _current_file_path
	var msg := _push_msg.text.strip_edges()
	if path == "": _set_status("Select a file first", true); return
	if msg == "": _set_status("Commit message required", true); return
	var b64 := Marshalls.utf8_to_base64(_file_content.text)
	_api.push_file(o, r, path, msg, b64, _current_file_sha, _current_file_branch)
	_set_status("Pushing file…", false)

func _do_pull_file() -> void:
	if _current_file_path == "": _set_status("Select a file first", true); return
	var local := _local_path.text.strip_edges()
	if local == "": local = "res://"
	var dest := local.path_join(_current_file_path.get_file())
	var fa := FileAccess.open(dest, FileAccess.WRITE)
	if not fa: _set_status("Cannot write to %s" % dest, true); return
	fa.store_string(_file_content.text)
	fa.close()
	_set_status("Pulled → %s" % dest, false)

func _scan_local() -> void:
	var local := _local_path.text.strip_edges()
	if local == "": local = "res://"
	_local_changed_files = []
	_file_tree.clear()
	_tree_files = []
	var dir := DirAccess.open(local)
	if not dir: _set_status("Cannot open %s" % local, true); return
	_scan_dir(dir, local, local)
	var ignored_count := 0
	var shown: Array = []
	for item in _tree_files:
		if _is_ignored(item["path"]):
			ignored_count += 1
		else:
			shown.append(item)
			_file_tree.add_item(item["path"])
	_tree_files = shown
	_local_changed_files = shown.map(func(i): return i["path"])
	_ignore_lbl.text = "Ignored: %d  |  Shown: %d" % [ignored_count, shown.size()]
	_set_status("Scanned: %d files (ignored %d)" % [shown.size(), ignored_count], false)

func _scan_dir(dir: DirAccess, base: String, current: String) -> void:
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := current.path_join(name)
			if dir.current_is_dir():
				var skip := false
				for ig in IGNORE_DIRS:
					if name == ig: skip = true; break
				if not skip:
					var sub := DirAccess.open(full)
					if sub: _scan_dir(sub, base, full)
			else:
				var rel := full.trim_prefix(base).trim_prefix("/")
				_tree_files.append({"path": rel, "local_full": full})
		name = dir.get_next()

func _get_selected_files() -> Array:
	var sel := _file_tree.get_selected_items()
	if sel.is_empty(): return []
	var out: Array = []
	for idx in sel:
		if idx < _tree_files.size():
			out.append(_tree_files[idx])
	return out

func _do_push_selected() -> void:
	var selected := _get_selected_files()
	if selected.is_empty(): _set_status("Select files first (tap to multi-select)", true); return
	var o := _file_owner.text.strip_edges()
	var r := _file_repo.text.strip_edges()
	var msg := _push_msg.text.strip_edges()
	var br := _file_branch.get_item_text(_file_branch.selected) if _file_branch.selected >= 0 else _ctx_branch
	if o == "" or r == "": _set_status("Owner+repo required", true); return
	if msg == "": _set_status("Commit message required", true); return
	_build_and_push(o, r, br, msg, selected)

func _do_push_multi() -> void:
	if _tree_files.is_empty(): _set_status("Scan local folder first", true); return
	var o := _file_owner.text.strip_edges()
	var r := _file_repo.text.strip_edges()
	var msg := _push_msg.text.strip_edges()
	var br := _file_branch.get_item_text(_file_branch.selected) if _file_branch.selected >= 0 else _ctx_branch
	if o == "" or r == "": _set_status("Owner+repo required", true); return
	if msg == "": _set_status("Commit message required", true); return
	_build_and_push(o, r, br, msg, _tree_files)

func _build_and_push(o: String, r: String, br: String, msg: String, items: Array) -> void:
	var files: Array = []
	for item in items:
		if not item is Dictionary: continue
		if not item.has("local_full"):
			# Remote file — use editor content
			if item.get("path","") == _current_file_path:
				files.append({"path": _current_file_path, "content_b64": Marshalls.utf8_to_base64(_file_content.text)})
			continue
		var fa := FileAccess.open(item["local_full"], FileAccess.READ)
		if not fa: continue
		var raw := fa.get_buffer(fa.get_length())
		fa.close()
		files.append({"path": item["path"], "content_b64": Marshalls.raw_to_base64(raw)})
	if files.is_empty(): _set_status("No readable files", true); return
	_set_status("Preparing push (%d files)…" % files.size(), false)
	_pending_push = {"owner": o, "repo": r, "branch": br, "files": files, "message": msg}
	_api.fetch_branches(o, r)

# ── Commits tab ───────────────────────────────────────────────────────────────

func _cm_fetch() -> void:
	var o := _cm_owner.text.strip_edges()
	var r := _cm_repo.text.strip_edges()
	if o == "" or r == "": _set_status("Owner+repo required", true); return
	_set_status("Loading commits…", false)
	_api.fetch_commits(o, r, _cm_branch.text.strip_edges(), _commits_page)

func _populate_commits(data: Array) -> void:
	_commits = data
	_cm_list.clear()
	for c in data:
		if not c is Dictionary: continue
		var co: Dictionary = c.get("commit",{})
		var msg: String = co.get("message","")
		var line := msg.split("\n")[0] if "\n" in msg else msg
		if line.length() > 68: line = line.substr(0,65) + "…"
		var sha: String = c.get("sha","")
		var short := sha.substr(0,7) if sha.length() >= 7 else sha
		var author: String = co.get("author",{}).get("name","?")
		var date: String = co.get("author",{}).get("date","")
		_cm_list.add_item("[%s] %s — %s %s" % [short, line, author, date.substr(0,10)])

func _on_commit_selected(idx: int) -> void:
	if idx < 0 or idx >= _commits.size(): return
	var c: Dictionary = _commits[idx]
	_fill_commit_detail(c)
	_api.fetch_commit(_cm_owner.text.strip_edges(), _cm_repo.text.strip_edges(), c.get("sha",""))

func _fill_commit_detail(c: Dictionary) -> void:
	var co: Dictionary = c.get("commit",{})
	var auth: Dictionary = co.get("author",{})
	var txt := "[b]%s[/b]\n" % c.get("sha","")
	txt += "Author: %s <%s>\n" % [auth.get("name","?"), auth.get("email","")]
	txt += "Date: %s\n\n%s\n\n" % [auth.get("date",""), co.get("message","")]
	txt += "[url]%s[/url]" % c.get("html_url","")
	_cm_detail.text = txt
	_diff_view.text = "Loading diff…"

func _show_diff(data: Dictionary) -> void:
	var files: Array = data.get("files",[])
	var out := ""
	for f in files:
		if not f is Dictionary: continue
		out += "=== %s  (+%d -%d) ===\n" % [f.get("filename",""), f.get("additions",0), f.get("deletions",0)]
		var patch: String = f.get("patch","") if f.get("patch") != null else "(binary)"
		out += patch + "\n\n"
	_diff_view.text = out if out != "" else "No diff available"

# ── PR tab ────────────────────────────────────────────────────────────────────

func _pr_fetch() -> void:
	var o := _pr_owner.text.strip_edges()
	var r := _pr_repo.text.strip_edges()
	if o == "" or r == "": _set_status("Owner+repo required", true); return
	var state: String = (["open","closed","all"] as Array)[_pr_state_opt.selected]
	_set_status("Loading PRs…", false)
	_api.fetch_pulls(o, r, state)

func _populate_prs(data: Array) -> void:
	_pulls = data
	_pr_list.clear()
	for pr in data:
		if not pr is Dictionary: continue
		var num: int = pr.get("number",0)
		var title: String = pr.get("title","")
		if title.length() > 55: title = title.substr(0,52)+"…"
		var state: String = pr.get("state","")
		_pr_list.add_item("%s #%d  %s" % ["●" if state=="open" else "○", num, title])

func _on_pr_selected(idx: int) -> void:
	if idx < 0 or idx >= _pulls.size(): return
	var pr: Dictionary = _pulls[idx]
	_selected_pr_number = pr.get("number",-1)
	var txt := "[b]#%d: %s[/b]\n" % [pr.get("number",0), pr.get("title","")]
	txt += "State: %s  |  %s → %s\n" % [pr.get("state",""),
		pr.get("head",{}).get("ref","?"), pr.get("base",{}).get("ref","?")]
	txt += "By: %s  |  Created: %s\n\n" % [
		pr.get("user",{}).get("login","?"), pr.get("created_at","").substr(0,10)]
	var body: String = pr.get("body","") if pr.get("body") != null else ""
	if body.length() > 500: body = body.substr(0,497)+"…"
	txt += body if body != "" else "_No description_"
	txt += "\n\n[url]%s[/url]" % pr.get("html_url","")
	_pr_detail.text = txt

func _do_pr_merge() -> void:
	if _selected_pr_number < 0: _set_status("Select a PR first", true); return
	_api.merge_pr(_pr_owner.text.strip_edges(), _pr_repo.text.strip_edges(), _selected_pr_number, "Merged via qugit")
	_set_status("Merging PR…", false)

func _do_pr_close() -> void:
	if _selected_pr_number < 0: _set_status("Select a PR first", true); return
	_api.close_pr(_pr_owner.text.strip_edges(), _pr_repo.text.strip_edges(), _selected_pr_number)
	_set_status("Closing PR…", false)

func _do_pr_create() -> void:
	var o := _pr_owner.text.strip_edges()
	var r := _pr_repo.text.strip_edges()
	var title := _pr_title.text.strip_edges()
	var head := _pr_head.text.strip_edges()
	var base := _pr_base.text.strip_edges()
	if o=="" or r=="" or title=="" or head=="" or base=="":
		_set_status("Owner, repo, title, head, base all required", true); return
	_api.create_pr(o, r, title, _pr_body.text, head, base)
	_set_status("Creating PR…", false)

# ── Issues tab ────────────────────────────────────────────────────────────────

func _is_fetch() -> void:
	var o := _is_owner.text.strip_edges()
	var r := _is_repo.text.strip_edges()
	if o == "" or r == "": _set_status("Owner+repo required", true); return
	var state: String = (["open","closed","all"] as Array)[_is_state_opt.selected]
	_set_status("Loading issues…", false)
	_api.fetch_issues(o, r, state)

func _populate_issues(data: Array) -> void:
	_issues = data
	_is_list.clear()
	for issue in data:
		if not issue is Dictionary: continue
		var num: int = issue.get("number",0)
		var title: String = issue.get("title","")
		if title.length() > 55: title = title.substr(0,52)+"…"
		var state: String = issue.get("state","")
		_is_list.add_item("%s #%d  %s" % ["●" if state=="open" else "○", num, title])

func _on_issue_selected(idx: int) -> void:
	if idx < 0 or idx >= _issues.size(): return
	var issue: Dictionary = _issues[idx]
	_selected_issue_number = issue.get("number",-1)
	var txt := "[b]#%d: %s[/b]\n" % [issue.get("number",0), issue.get("title","")]
	txt += "State: %s  |  By: %s  |  %s\n\n" % [
		issue.get("state",""), issue.get("user",{}).get("login","?"),
		issue.get("created_at","").substr(0,10)]
	var labels: Array = issue.get("labels",[])
	if not labels.is_empty():
		var lnames: Array[String] = []
		for l in labels:
			if l is Dictionary: lnames.append(l.get("name",""))
		txt += "Labels: %s\n\n" % ", ".join(lnames)
	var body: String = issue.get("body","") if issue.get("body") != null else ""
	if body.length() > 500: body = body.substr(0,497)+"…"
	txt += body if body != "" else "_No description_"
	txt += "\n\n[url]%s[/url]" % issue.get("html_url","")
	_is_detail.text = txt

func _do_issue_close() -> void:
	if _selected_issue_number < 0: _set_status("Select an issue first", true); return
	_api.close_issue(_is_owner.text.strip_edges(), _is_repo.text.strip_edges(), _selected_issue_number)
	_set_status("Closing issue…", false)

func _do_issue_create() -> void:
	var o := _is_owner.text.strip_edges()
	var r := _is_repo.text.strip_edges()
	var title := _is_title.text.strip_edges()
	if o=="" or r=="" or title=="": _set_status("Owner, repo, title required", true); return
	_api.create_issue(o, r, title, _is_body.text)
	_set_status("Creating issue…", false)

# ── API response router ───────────────────────────────────────────────────────

func _on_done(tag: String, data: Variant) -> void:
	match tag:
		"user":
			if data is Dictionary:
				var login: String = data.get("login","?")
				_set_status("Connected as %s" % login, false)
				_save_token(_api.get_token())
				_api.fetch_my_repos(1)
		"repos":
			if data is Array:
				_populate_repos(data)
				_set_status("Loaded %d repos" % data.size(), false)
		"search_repos":
			if data is Dictionary:
				var items: Array = data.get("items",[])
				_populate_repos(items)
				_set_status("Found %d results" % data.get("total_count",0), false)
		"create_repo":
			if data is Dictionary:
				_set_status("Repo created: %s" % data.get("full_name",""), false)
				_api.fetch_my_repos(1)
		"delete_repo":
			_set_status("Repo deleted", false)
			_api.fetch_my_repos(1)
		"branches":
			if data is Array:
				_populate_branches(data)
				_set_status("Loaded %d branches" % data.size(), false)
				if not _pending_push.is_empty():
					_execute_pending_push(data)
		"create_branch":
			_set_status("Branch created", false); _br_fetch()
		"delete_branch":
			_set_status("Branch deleted", false); _br_fetch()
		"merge":
			if data is Dictionary:
				_set_status("Merged: %s" % data.get("message","done"), false)
		"tree":
			if data is Dictionary:
				_populate_tree(data)
				_set_status("Loaded %d files (ignored hidden/.uid/.import)" % _tree_files.size(), false)
		"file_meta":
			if data is Dictionary:
				_current_file_sha = data.get("sha","")
				var raw_b64: String = data.get("content","")
				raw_b64 = raw_b64.replace("\n","")
				_file_content.text = Marshalls.base64_to_utf8(raw_b64) if raw_b64 != "" else "(binary)"
		"push_file":
			if data is Dictionary:
				_set_status("File pushed", false)
				_current_file_sha = data.get("content",{}).get("sha", _current_file_sha)
		"push_commit":
			_pending_push = {}
			_set_status("Push complete ✓", false)
		"commits":
			if data is Array:
				_populate_commits(data)
				_set_status("Loaded %d commits" % data.size(), false)
		"commit_detail":
			if data is Dictionary: _show_diff(data)
		"pulls":
			if data is Array:
				_populate_prs(data)
				_set_status("Loaded %d PRs" % data.size(), false)
		"create_pr":
			if data is Dictionary:
				_set_status("PR #%d created" % data.get("number",0), false)
				_pr_fetch()
		"merge_pr":
			_set_status("PR merged", false); _pr_fetch()
		"close_pr":
			_set_status("PR closed", false); _pr_fetch()
		"issues":
			if data is Array:
				_populate_issues(data)
				_set_status("Loaded %d issues" % data.size(), false)
		"create_issue":
			if data is Dictionary:
				_set_status("Issue #%d created" % data.get("number",0), false)
				_is_fetch()
		"close_issue":
			_set_status("Issue closed", false); _is_fetch()

func _on_fail(tag: String, msg: String) -> void:
	_pending_push = {}
	_set_status("[%s] %s" % [tag, msg], true)

# ── Multi-push flow ───────────────────────────────────────────────────────────

func _execute_pending_push(branches_data: Array) -> void:
	var push := _pending_push
	_pending_push = {}
	var br: String = push.get("branch","main")
	var branch_sha := ""
	for b in branches_data:
		if not b is Dictionary: continue
		if b.get("name","") == br:
			branch_sha = b.get("commit",{}).get("sha","")
			break
	if branch_sha == "":
		_set_status("Branch not found: %s" % br, true); return
	_pending_push = push
	_pending_push["parent_sha"] = branch_sha
	_api.fetch_commit(push["owner"], push["repo"], branch_sha)

func _on_done_push_commit_info(data: Dictionary) -> void:
	if _pending_push.is_empty(): return
	var tree_sha: String = data.get("commit",{}).get("tree",{}).get("sha","")
	if tree_sha == "":
		_set_status("Could not get tree SHA", true)
		_pending_push = {}; return
	var push := _pending_push
	_pending_push = {}
	_api.push_commit(push["owner"], push["repo"], push["branch"],
		push["files"], push["message"], push["parent_sha"], tree_sha)

func _on_done_patched(tag: String, data: Variant) -> void:
	if tag == "commit_detail" and not _pending_push.is_empty() and data is Dictionary:
		_on_done_push_commit_info(data)
	else:
		_on_done(tag, data)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _set_status(msg: String, err: bool) -> void:
	if _status_lbl:
		_status_lbl.text = msg
		_status_lbl.add_theme_color_override("font_color",
			Color.TOMATO if err else Color(0.85,0.85,0.85,1))
