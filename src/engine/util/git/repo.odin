package git

import "core:strconv"
import "core:strings"

Repo :: struct {
	path: string,
}

Status_Entry :: struct {
	index:    u8,
	worktree: u8,
	path:     string,
}

Commit :: struct {
	hash:    string,
	author:  string,
	email:   string,
	date:    string,
	subject: string,
}

open :: proc(path: string) -> Repo {
	return Repo{path = path}
}

init :: proc(
	path: string,
	bare := false,
	initial_branch := "",
	allocator := context.allocator,
) -> Result {
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "init")
	if bare {
		append(&args, "--bare")
	}
	if initial_branch != "" {
		append(&args, "-b", initial_branch)
	}
	append(&args, path)
	return run(args[:], "", allocator)
}

clone :: proc(
	url, dest: string,
	branch := "",
	depth := 0,
	allocator := context.allocator,
) -> Result {
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "clone")
	if branch != "" {
		append(&args, "--branch", branch)
	}
	buf: [32]byte
	if depth > 0 {
		append(&args, "--depth", strconv.write_int(buf[:], i64(depth), 10))
	}
	append(&args, url, dest)
	return run(args[:], "", allocator)
}

is_repo :: proc(repo: Repo) -> bool {
	text, ok := run_text({"rev-parse", "--is-inside-work-tree"}, repo.path, context.temp_allocator)
	return ok && text == "true"
}

root :: proc(repo: Repo, allocator := context.allocator) -> (string, bool) {
	return run_text({"rev-parse", "--show-toplevel"}, repo.path, allocator)
}

current_branch :: proc(repo: Repo, allocator := context.allocator) -> (string, bool) {
	return run_text({"branch", "--show-current"}, repo.path, allocator)
}

head_commit :: proc(repo: Repo, short := false, allocator := context.allocator) -> (string, bool) {
	if short {
		return run_text({"rev-parse", "--short", "HEAD"}, repo.path, allocator)
	}
	return run_text({"rev-parse", "HEAD"}, repo.path, allocator)
}

remote_url :: proc(
	repo: Repo,
	name := "origin",
	allocator := context.allocator,
) -> (
	string,
	bool,
) {
	return run_text({"remote", "get-url", name}, repo.path, allocator)
}

config_get :: proc(repo: Repo, key: string, allocator := context.allocator) -> (string, bool) {
	return run_text({"config", "--get", key}, repo.path, allocator)
}

config_set :: proc(
	repo: Repo,
	key, value: string,
	global := false,
	allocator := context.allocator,
) -> Result {
	if global {
		return run({"config", "--global", key, value}, repo.path, allocator)
	}
	return run({"config", key, value}, repo.path, allocator)
}

add :: proc(repo: Repo, paths: ..string, allocator := context.allocator) -> Result {
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "add")
	if len(paths) == 0 {
		append(&args, "--all")
	} else {
		append(&args, "--")
		append(&args, ..paths)
	}
	return run(args[:], repo.path, allocator)
}

commit :: proc(
	repo: Repo,
	message: string,
	all := false,
	allow_empty := false,
	allocator := context.allocator,
) -> Result {
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "commit")
	if all {
		append(&args, "--all")
	}
	if allow_empty {
		append(&args, "--allow-empty")
	}
	append(&args, "-m", message)
	return run(args[:], repo.path, allocator)
}

checkout :: proc(repo: Repo, target: string, allocator := context.allocator) -> Result {
	return run({"checkout", target}, repo.path, allocator)
}

create_branch :: proc(
	repo: Repo,
	name: string,
	checkout_after := true,
	allocator := context.allocator,
) -> Result {
	if checkout_after {
		return run({"checkout", "-b", name}, repo.path, allocator)
	}
	return run({"branch", name}, repo.path, allocator)
}

fetch :: proc(repo: Repo, remote := "", allocator := context.allocator) -> Result {
	if remote == "" {
		return run({"fetch"}, repo.path, allocator)
	}
	return run({"fetch", remote}, repo.path, allocator)
}

pull :: proc(repo: Repo, allocator := context.allocator) -> Result {
	return run({"pull"}, repo.path, allocator)
}

push :: proc(
	repo: Repo,
	remote := "",
	branch := "",
	set_upstream := false,
	allocator := context.allocator,
) -> Result {
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "push")
	if set_upstream {
		append(&args, "--set-upstream")
	}
	if remote != "" {
		append(&args, remote)
	}
	if branch != "" {
		append(&args, branch)
	}
	return run(args[:], repo.path, allocator)
}

diff :: proc(
	repo: Repo,
	staged := false,
	allocator := context.allocator,
) -> (
	text: string,
	ok: bool,
) {
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "diff")
	if staged {
		append(&args, "--staged")
	}
	result := run(args[:], repo.path, allocator)
	if !success(result) {
		destroy_result(result, allocator)
		return "", false
	}
	delete(result.stderr, allocator)
	return result.stdout, true
}

status :: proc(repo: Repo, allocator := context.allocator) -> (entries: []Status_Entry, ok: bool) {
	result := run(
		{"status", "--porcelain=v1", "-z", "--untracked-files=all"},
		repo.path,
		context.temp_allocator,
	)
	if !success(result) {
		return nil, false
	}

	parts, _ := strings.split(result.stdout, "\x00", context.temp_allocator)
	list := make([dynamic]Status_Entry, allocator)

	i := 0
	for i < len(parts) {
		part := parts[i]
		i += 1
		if len(part) < 4 {
			continue
		}
		x, y := part[0], part[1]
		if x == 'R' || x == 'C' || y == 'R' || y == 'C' {
			i += 1
		}
		append(
			&list,
			Status_Entry{index = x, worktree = y, path = strings.clone(part[3:], allocator)},
		)
	}
	return list[:], true
}

destroy_status :: proc(entries: []Status_Entry, allocator := context.allocator) {
	for entry in entries {
		delete(entry.path, allocator)
	}
	delete(entries, allocator)
}

is_clean :: proc(repo: Repo) -> bool {
	entries, ok := status(repo, context.temp_allocator)
	return ok && len(entries) == 0
}

log :: proc(
	repo: Repo,
	max_count := 0,
	allocator := context.allocator,
) -> (
	commits: []Commit,
	ok: bool,
) {
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "log", "--format=%H%x1f%an%x1f%ae%x1f%aI%x1f%s%x1e")
	buf: [32]byte
	if max_count > 0 {
		append(&args, "-n", strconv.write_int(buf[:], i64(max_count), 10))
	}

	result := run(args[:], repo.path, context.temp_allocator)
	if !success(result) {
		return nil, false
	}

	records, _ := strings.split(result.stdout, "\x1e", context.temp_allocator)
	list := make([dynamic]Commit, allocator)

	for record in records {
		trimmed := strings.trim_left_space(record)
		if len(trimmed) == 0 {
			continue
		}
		fields, _ := strings.split(trimmed, "\x1f", context.temp_allocator)
		if len(fields) < 5 {
			continue
		}
		append(
			&list,
			Commit {
				hash = strings.clone(fields[0], allocator),
				author = strings.clone(fields[1], allocator),
				email = strings.clone(fields[2], allocator),
				date = strings.clone(fields[3], allocator),
				subject = strings.clone(fields[4], allocator),
			},
		)
	}
	return list[:], true
}

destroy_commits :: proc(commits: []Commit, allocator := context.allocator) {
	for commit in commits {
		delete(commit.hash, allocator)
		delete(commit.author, allocator)
		delete(commit.email, allocator)
		delete(commit.date, allocator)
		delete(commit.subject, allocator)
	}
	delete(commits, allocator)
}

branches :: proc(repo: Repo, allocator := context.allocator) -> (names: []string, ok: bool) {
	return list_lines({"branch", "--format=%(refname:short)"}, repo.path, allocator)
}

tags :: proc(repo: Repo, allocator := context.allocator) -> (names: []string, ok: bool) {
	return list_lines({"tag", "--list"}, repo.path, allocator)
}

destroy_lines :: proc(lines: []string, allocator := context.allocator) {
	for line in lines {
		delete(line, allocator)
	}
	delete(lines, allocator)
}

@(private)
list_lines :: proc(
	args: []string,
	dir: string,
	allocator := context.allocator,
) -> (
	lines: []string,
	ok: bool,
) {
	result := run(args, dir, context.temp_allocator)
	if !success(result) {
		return nil, false
	}

	raw, _ := strings.split_lines(result.stdout, context.temp_allocator)
	list := make([dynamic]string, allocator)
	for line in raw {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 {
			continue
		}
		append(&list, strings.clone(trimmed, allocator))
	}
	return list[:], true
}
