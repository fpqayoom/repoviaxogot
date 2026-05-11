@tool
extends Node

signal request_completed(tag: String, data: Variant)
signal request_failed(tag: String, message: String)
signal rate_limit_updated(remaining: int)

const BASE := "https://api.github.com"
const ACCEPT := "application/vnd.github+json"
const VER := "2022-11-28"

var _token := ""
var _rate := 60

# ── Auth ──────────────────────────────────────────────────────────────────────

func set_token(t: String) -> void: _token = t.strip_edges()
func get_token() -> String: return _token
func has_token() -> bool: return _token.length() > 0
func rate_left() -> int: return _rate

# ── User ──────────────────────────────────────────────────────────────────────

func fetch_user() -> void: _do_get("/user", "user")

# ── Repos ─────────────────────────────────────────────────────────────────────

func fetch_my_repos(page := 1) -> void:
	_do_get("/user/repos?sort=updated&per_page=30&page=%d" % page, "repos")

func search_repos(q: String, page := 1) -> void:
	_do_get("/search/repositories?q=%s&sort=updated&per_page=20&page=%d" % [q.uri_encode(), page], "search_repos")

func create_repo(name: String, desc: String, private: bool) -> void:
	_do_post("/user/repos", {"name": name, "description": desc, "private": private, "auto_init": true}, "create_repo")

func delete_repo(owner: String, repo: String) -> void:
	_do_delete("/repos/%s/%s" % [owner, repo], "delete_repo")

func fetch_repo(owner: String, repo: String) -> void:
	_do_get("/repos/%s/%s" % [owner, repo], "repo")

# ── Branches ──────────────────────────────────────────────────────────────────

func fetch_branches(owner: String, repo: String) -> void:
	_do_get("/repos/%s/%s/branches?per_page=50" % [owner, repo], "branches")

func create_branch(owner: String, repo: String, new_branch: String, from_sha: String) -> void:
	_do_post("/repos/%s/%s/git/refs" % [owner, repo],
		{"ref": "refs/heads/" + new_branch, "sha": from_sha}, "create_branch")

func delete_branch(owner: String, repo: String, branch: String) -> void:
	_do_delete("/repos/%s/%s/git/refs/heads/%s" % [owner, repo, branch.uri_encode()], "delete_branch")

func merge_branches(owner: String, repo: String, base: String, head: String, msg: String) -> void:
	_do_post("/repos/%s/%s/merges" % [owner, repo],
		{"base": base, "head": head, "commit_message": msg}, "merge")

# ── Commits ───────────────────────────────────────────────────────────────────

func fetch_commits(owner: String, repo: String, branch := "", page := 1) -> void:
	var path := "/repos/%s/%s/commits?per_page=30&page=%d" % [owner, repo, page]
	if branch != "":
		path += "&sha=" + branch.uri_encode()
	_do_get(path, "commits")

func fetch_commit(owner: String, repo: String, sha: String) -> void:
	_do_get("/repos/%s/%s/commits/%s" % [owner, repo, sha], "commit_detail")

# ── Files / Contents ──────────────────────────────────────────────────────────

func fetch_tree(owner: String, repo: String, branch: String) -> void:
	_do_get("/repos/%s/%s/git/trees/%s?recursive=1" % [owner, repo, branch.uri_encode()], "tree")

func fetch_file_meta(owner: String, repo: String, path: String, branch: String) -> void:
	_do_get("/repos/%s/%s/contents/%s?ref=%s" % [owner, repo, path.uri_encode(), branch.uri_encode()], "file_meta")

func fetch_file_raw(owner: String, repo: String, path: String, branch: String) -> void:
	_do_get("/repos/%s/%s/contents/%s?ref=%s" % [owner, repo, path.uri_encode(), branch.uri_encode()], "file_raw")

# Push a single file (create or update).
# content_b64: base64-encoded file content
# sha: existing file SHA if updating, "" if creating
func push_file(owner: String, repo: String, path: String, message: String,
		content_b64: String, sha: String, branch: String) -> void:
	var body: Dictionary = {
		"message": message,
		"content": content_b64,
		"branch": branch
	}
	if sha != "":
		body["sha"] = sha
	_do_put("/repos/%s/%s/contents/%s" % [owner, repo, path.uri_encode()], body, "push_file")

# Full multi-file push via Git Data API:
# files: Array of {path, content_b64}
# parent_sha: SHA of the commit to build on top of
# tree_sha: base tree SHA
func push_commit(owner: String, repo: String, branch: String,
		files: Array, message: String, parent_sha: String, tree_sha: String) -> void:
	# Step 1: create blobs for each file, then we chain the rest in signal handlers
	var state := {
		"owner": owner, "repo": repo, "branch": branch,
		"files": files, "message": message,
		"parent_sha": parent_sha, "base_tree_sha": tree_sha,
		"blobs": [], "idx": 0
	}
	_push_next_blob(state)

func _push_next_blob(state: Dictionary) -> void:
	var idx: int = state["idx"]
	var files: Array = state["files"]
	if idx >= files.size():
		_push_create_tree(state)
		return
	var file: Dictionary = files[idx]
	var body := {"content": file["content_b64"], "encoding": "base64"}
	var owner: String = state["owner"]
	var repo: String = state["repo"]
	var http := _make_http()
	http.request_completed.connect(func(res, code, _h, raw):
		http.queue_free()
		if res != HTTPRequest.RESULT_SUCCESS or code >= 400:
			emit_signal("request_failed", "push_commit", "Blob upload failed (file %d)" % idx)
			return
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if not parsed is Dictionary:
			emit_signal("request_failed", "push_commit", "Blob parse failed")
			return
		state["blobs"].append({"path": file["path"], "sha": parsed.get("sha",""), "mode": "100644", "type": "blob"})
		state["idx"] = idx + 1
		_push_next_blob(state)
	)
	http.request(BASE + "/repos/%s/%s/git/blobs" % [owner, state["repo"]],
		_headers(), HTTPClient.METHOD_POST, JSON.stringify(body))

func _push_create_tree(state: Dictionary) -> void:
	var body := {"base_tree": state["base_tree_sha"], "tree": state["blobs"]}
	var http := _make_http()
	var owner: String = state["owner"]
	var repo: String = state["repo"]
	http.request_completed.connect(func(res, code, _h, raw):
		http.queue_free()
		if res != HTTPRequest.RESULT_SUCCESS or code >= 400:
			emit_signal("request_failed", "push_commit", "Tree creation failed")
			return
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if not parsed is Dictionary:
			return
		state["new_tree_sha"] = parsed.get("sha", "")
		_push_create_commit(state)
	)
	http.request(BASE + "/repos/%s/%s/git/trees" % [owner, repo],
		_headers(), HTTPClient.METHOD_POST, JSON.stringify(body))

func _push_create_commit(state: Dictionary) -> void:
	var body := {
		"message": state["message"],
		"tree": state["new_tree_sha"],
		"parents": [state["parent_sha"]]
	}
	var owner: String = state["owner"]
	var repo: String = state["repo"]
	var http := _make_http()
	http.request_completed.connect(func(res, code, _h, raw):
		http.queue_free()
		if res != HTTPRequest.RESULT_SUCCESS or code >= 400:
			emit_signal("request_failed", "push_commit", "Commit creation failed")
			return
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if not parsed is Dictionary:
			return
		state["commit_sha"] = parsed.get("sha", "")
		_push_update_ref(state)
	)
	http.request(BASE + "/repos/%s/%s/git/commits" % [owner, repo],
		_headers(), HTTPClient.METHOD_POST, JSON.stringify(body))

func _push_update_ref(state: Dictionary) -> void:
	var branch: String = state["branch"]
	var body := {"sha": state["commit_sha"], "force": false}
	var owner: String = state["owner"]
	var repo: String = state["repo"]
	var http := _make_http()
	http.request_completed.connect(func(res, code, _h, raw):
		http.queue_free()
		if res != HTTPRequest.RESULT_SUCCESS or code >= 400:
			emit_signal("request_failed", "push_commit", "Ref update failed")
			return
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		emit_signal("request_completed", "push_commit", parsed if parsed != null else {})
	)
	http.request(BASE + "/repos/%s/%s/git/refs/heads/%s" % [owner, repo, branch.uri_encode()],
		_headers(), HTTPClient.METHOD_PATCH, JSON.stringify(body))

# ── Pull Requests ─────────────────────────────────────────────────────────────

func fetch_pulls(owner: String, repo: String, state := "open", page := 1) -> void:
	_do_get("/repos/%s/%s/pulls?state=%s&per_page=30&page=%d" % [owner, repo, state, page], "pulls")

func create_pr(owner: String, repo: String, title: String, body: String, head: String, base: String) -> void:
	_do_post("/repos/%s/%s/pulls" % [owner, repo],
		{"title": title, "body": body, "head": head, "base": base}, "create_pr")

func merge_pr(owner: String, repo: String, number: int, msg: String) -> void:
	_do_put("/repos/%s/%s/pulls/%d/merge" % [owner, repo, number],
		{"commit_message": msg, "merge_method": "merge"}, "merge_pr")

func close_pr(owner: String, repo: String, number: int) -> void:
	_do_patch("/repos/%s/%s/pulls/%d" % [owner, repo, number], {"state": "closed"}, "close_pr")

func fetch_pr_files(owner: String, repo: String, number: int) -> void:
	_do_get("/repos/%s/%s/pulls/%d/files" % [owner, repo, number], "pr_files")

# ── Issues ────────────────────────────────────────────────────────────────────

func fetch_issues(owner: String, repo: String, state := "open", page := 1) -> void:
	_do_get("/repos/%s/%s/issues?state=%s&per_page=30&page=%d" % [owner, repo, state, page], "issues")

func create_issue(owner: String, repo: String, title: String, body: String) -> void:
	_do_post("/repos/%s/%s/issues" % [owner, repo], {"title": title, "body": body}, "create_issue")

func close_issue(owner: String, repo: String, number: int) -> void:
	_do_patch("/repos/%s/%s/issues/%d" % [owner, repo, number], {"state": "closed"}, "close_issue")

# ── HTTP primitives ───────────────────────────────────────────────────────────

func _headers() -> PackedStringArray:
	var h: PackedStringArray = [
		"Accept: " + ACCEPT,
		"X-GitHub-Api-Version: " + VER,
		"User-Agent: qugit-godot-plugin",
		"Content-Type: application/json"
	]
	if _token != "":
		h.append("Authorization: Bearer " + _token)
	return h

func _make_http() -> HTTPRequest:
	var h := HTTPRequest.new()
	h.use_threads = true
	add_child(h)
	return h

func _do_get(path: String, tag: String) -> void:
	_fire(path, HTTPClient.METHOD_GET, "", tag)

func _do_post(path: String, body: Dictionary, tag: String) -> void:
	_fire(path, HTTPClient.METHOD_POST, JSON.stringify(body), tag)

func _do_put(path: String, body: Dictionary, tag: String) -> void:
	_fire(path, HTTPClient.METHOD_PUT, JSON.stringify(body), tag)

func _do_patch(path: String, body: Dictionary, tag: String) -> void:
	_fire(path, HTTPClient.METHOD_PATCH, JSON.stringify(body), tag)

func _do_delete(path: String, tag: String) -> void:
	_fire(path, HTTPClient.METHOD_DELETE, "", tag)

func _fire(path: String, method: int, body: String, tag: String) -> void:
	var http := _make_http()
	var _tag := tag
	http.request_completed.connect(func(res, code, hdrs, raw):
		http.queue_free()
		_handle(res, code, hdrs, raw, _tag)
	)
	var err := http.request(BASE + path, _headers(), method, body)
	if err != OK:
		http.queue_free()
		emit_signal("request_failed", tag, "HTTP setup error %d" % err)

func _handle(res: int, code: int, hdrs: PackedStringArray, raw: PackedByteArray, tag: String) -> void:
	for h in hdrs:
		var l := h.to_lower()
		if l.begins_with("x-ratelimit-remaining:"):
			_rate = l.split(":")[1].strip_edges().to_int()
			emit_signal("rate_limit_updated", _rate)
	if res != HTTPRequest.RESULT_SUCCESS:
		emit_signal("request_failed", tag, "Network error %d" % res)
		return
	var text := raw.get_string_from_utf8()
	if code == 204:
		emit_signal("request_completed", tag, {})
		return
	var parsed = JSON.parse_string(text)
	if parsed == null:
		emit_signal("request_failed", tag, "JSON parse failed (HTTP %d)" % code)
		return
	if code >= 400:
		var msg: String = parsed.get("message", "HTTP %d" % code) if parsed is Dictionary else "HTTP %d" % code
		emit_signal("request_failed", tag, msg)
		return
	emit_signal("request_completed", tag, parsed)
