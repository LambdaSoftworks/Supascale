teardown_project() {
	local id="$1"
	local dir="$HOME/$id/supabase/docker"

	if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
		docker compose -f "$dir/docker-compose.yml" --project-name "$id" down -v --remove-orphans >/dev/null 2>&1 || true
	fi

	rm -rf "$HOME/$id"
}
