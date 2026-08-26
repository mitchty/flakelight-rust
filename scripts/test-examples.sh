#!/usr/bin/env sh
#-*-mode: Shell-script; coding: utf-8;-*-
# Description: Test all of this beast from the weasts examples.
set "${SETOPTS:--eu}"

# Usage:
#   scripts/test-examples.sh [--update-cargo-lock] [example...]
#
# With no example names given, every examples/*/flake.nix is tested.
#
# Examples:
#   scripts/test-examples.sh                        # test everything, latest, no persisting
#   scripts/test-examples.sh multi-binary           # test just one example
#   scripts/test-examples.sh --update-cargo-lock    # test everything, keep passing Cargo.lock updates staged in git
root=$(git rev-parse --show-toplevel) || exit 126
cd "$root" || exit 126

update_cargo_lock=false
examples=""

for arg in "$@"; do
	case "$arg" in
	--update-cargo-lock)
		update_cargo_lock=true
		;;
	-h | --help)
		sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		examples="$examples $arg"
		;;
	esac
done

if [ -z "$examples" ]; then
	list_file=$(mktemp)
	find examples -mindepth 2 -maxdepth 2 -name flake.nix | sort >"$list_file"
	while IFS= read -r flake; do
		examples="$examples $(basename "$(dirname "$flake")")"
	done <"$list_file"
	rm -f "$list_file"
fi

failed=""
updated=""

for example in $examples; do
	dir="examples/$example"

	if [ ! -f "$dir/flake.nix" ]; then
		printf "warn: skipping '%s' no %s/flake.nix found\n" "$example" "$dir" >&2
		failed="$failed $example"
		continue
	fi

	printf "testing: %s\n" "$example"

	lock_backup=""
	if [ -f "$dir/Cargo.lock" ]; then
		lock_backup=$(mktemp)
		cp "$dir/Cargo.lock" "$lock_backup"
	fi

	status=0
	(
		cd "$dir"
		printf "nix flake lock\n" >&2
		nix flake lock

		# Use nix develop to ensure we're using the flakes deps only
		printf "cargo update\n" >&2
		nix develop --command cargo update --verbose

		git -C "$root" add -f "$dir/flake.lock" "$dir/Cargo.lock"

		printf "nix flake check -L\n" >&2
		nix flake check -L
	) || status=$?

	if [ "$status" -ne 0 ]; then
		printf "fatal: %s failed to check\n" "$example" >&2
		failed="$failed $example"
	else
		printf "ok: %s\n" "$example" >&2
	fi

	if [ "$update_cargo_lock" = true ] && [ "$status" -eq 0 ]; then
		if [ -n "$lock_backup" ] && cmp -s "$lock_backup" "$dir/Cargo.lock"; then
			printf "%s: Cargo.lock unchanged, nothing to update\n" "$example" >&2
		else
			printf "%s: keeping updated Cargo.lock as latest working snapshot\n" "$example"
			updated="$updated $example"
		fi
	elif [ -n "$lock_backup" ]; then
		cp "$lock_backup" "$dir/Cargo.lock"
		git add -f "$dir/Cargo.lock"
	fi
	[ -n "$lock_backup" ] && rm -f "$lock_backup"

	# flake.lock is never persisted for examples.
	git reset -q -- "$dir/flake.lock" || true
	rm -f "$dir/flake.lock"
done

for example in $examples; do
	case " $failed " in
	*" $example "*)
		printf "failed: %s\n" "$example" >&2
		;;
	*)
		printf "ok: %s\n" "$example" >&2
		;;
	esac
done

if [ -n "$updated" ]; then
	printf "Cargo.lock was updated committing is up to the caller.\n" >&2
fi

if [ -n "$failed" ]; then
	printf "total failures: %s\n" "${failed}" >&2
	exit 1
fi
