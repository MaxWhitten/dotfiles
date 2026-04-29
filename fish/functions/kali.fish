function kali --description "Kali raw Podman + LUKS vault manager (no Distrobox, no host home bind)"
    # --- config defaults ---
    set -l vault "$HOME/kali-data"
    set -l luks_file "$HOME/vaults/kali-data.luks"
    set -l mapper_name "kali_data"

    set -l box_name "kali"
    set -l image "docker.io/kalilinux/kali-rolling:latest"

    set -l enc_home "$vault/home"
    set -l graphroot "$vault/podman-storage"

    # Container-visible HOME path (clean path, no host ~/... leak)
    set -l container_home "/home/kali"

    # Optional overrides (set -U ...)
    if set -q KALI_LUKS_FILE
        set luks_file "$KALI_LUKS_FILE"
    end
    if set -q KALI_VAULT_PATH
        set vault "$KALI_VAULT_PATH"
        set enc_home "$vault/home"
        set graphroot "$vault/podman-storage"
    end
    if set -q KALI_MAPPER_NAME
        set mapper_name "$KALI_MAPPER_NAME"
    end
    if set -q KALI_BOX_NAME
        set box_name "$KALI_BOX_NAME"
    end
    if set -q KALI_IMAGE
        set image "$KALI_IMAGE"
    end
    if set -q KALI_CONTAINER_HOME
        set container_home "$KALI_CONTAINER_HOME"
    end

    # Host runtime/session values (used for GUI apps)
    set -l uid (id -u)
    set -l gid (id -g)
    set -l runtime_dir ""
    if set -q XDG_RUNTIME_DIR
        set runtime_dir "$XDG_RUNTIME_DIR"
    else
        set runtime_dir "/run/user/$uid"
    end

    set -l cmd "help"
    if test (count $argv) -gt 0
        set cmd $argv[1]
        set -e argv[1]
    end

    # ---------- helper-ish local checks (inline, no nested funcs) ----------
    # podman graphroot check (used by most subcommands)
    if contains -- "$cmd" create recreate rebuild a attach r run s spawn where start stop
        # vault mount check is handled per-command; don't force it for help/debug
        true
    end

    # ---------- help ----------
    if contains -- "$cmd" help -h --help
        echo "Usage:"
        echo "  kali o|open                    Open + mount LUKS vault"
        echo "  kali c|close                   Unmount + close LUKS vault"
        echo "  kali init-storage              Configure rootless Podman graphroot on LUKS"
        echo "  kali create                    Create raw Podman Kali container (no host ~ bind)"
        echo "  kali recreate|rebuild          Recreate container"
        echo "  kali destroy                   Remove container"
        echo "  kali start                     Start container"
        echo "  kali stop                      Stop container"
        echo "  kali a|attach                  Shell into container (starts in container HOME)"
        echo "  kali r|run <cmd> [args...]     Run command in container"
        echo "  kali s|spawn <app> [args...]   Spawn GUI/app in container"
        echo "  kali where                     Show HOME/PWD/mounts inside container"
        echo "  kali status|st                 Show vault/podman/container status"
        echo "  kali debug                     Show resolved config + GUI mount candidates"
        echo
        echo "Optional overrides (fish universal vars):"
        echo "  set -U KALI_LUKS_FILE /path/to/file"
        echo "  set -U KALI_VAULT_PATH /path/to/mount"
        echo "  set -U KALI_MAPPER_NAME mapper_name"
        echo "  set -U KALI_BOX_NAME container_name"
        echo "  set -U KALI_IMAGE docker.io/kalilinux/kali-rolling:latest"
        echo "  set -U KALI_CONTAINER_HOME /home/kali"
        return 0
    end

    # ---------- open vault ----------
    if contains -- "$cmd" o open
        mkdir -p "$vault"

        if mountpoint -q "$vault"
            mkdir -p "$enc_home" "$graphroot"
            echo "Vault already mounted at $vault"
            return 0
        end

        if test -e "/dev/mapper/$mapper_name"
            echo "Mapper /dev/mapper/$mapper_name is already open, mounting..."
            sudo mount "/dev/mapper/$mapper_name" "$vault"; or return 1
            sudo chown $USER:$USER "$vault"; or return 1
            mkdir -p "$enc_home" "$graphroot"
            echo "Vault ready at $vault"
            return 0
        end

        if not test -f "$luks_file"
            echo "Vault file not found: $luks_file" >&2
            echo "Tip: set -U KALI_LUKS_FILE /actual/path/to/file" >&2
            return 1
        end

        echo "Opening LUKS vault ($luks_file) as mapper '$mapper_name'..."
        sudo cryptsetup open "$luks_file" "$mapper_name"; or return 1

        echo "Mounting vault..."
        sudo mount "/dev/mapper/$mapper_name" "$vault"; or return 1
        sudo chown $USER:$USER "$vault"; or return 1

        mkdir -p "$enc_home" "$graphroot"
        echo "Vault ready at $vault"
        return 0
    end

    # ---------- close vault ----------
    if contains -- "$cmd" c close
        # stop container first so graphroot isn't busy
        podman inspect "$box_name" >/dev/null 2>&1
        if test $status -eq 0
            set -l running_state (podman inspect --format '{{.State.Running}}' "$box_name" 2>/dev/null)
            if test "$running_state" = "true"
                echo "Stopping container $box_name..."
                podman stop "$box_name" >/dev/null; or return 1
            end
        end

        if mountpoint -q "$vault"
            echo "Unmounting $vault..."
            sudo umount "$vault"; or return 1
        else
            echo "Vault not mounted at $vault"
        end

        if test -e "/dev/mapper/$mapper_name"
            echo "Closing mapper '$mapper_name'..."
            sudo cryptsetup close "$mapper_name"; or return 1
        else
            echo "Mapper '$mapper_name' not open"
        end

        echo "Vault closed"
        return 0
    end

    # ---------- init podman storage on LUKS ----------
    if contains -- "$cmd" init-storage initstore
        if not mountpoint -q "$vault"
            kali open; or return 1
        end

        mkdir -p ~/.config/containers "$graphroot"
        printf "[storage]\ndriver = \"overlay\"\ngraphroot = \"%s\"\n" "$graphroot" > ~/.config/containers/storage.conf

        echo "Wrote ~/.config/containers/storage.conf"
        podman info --format 'graphRoot={{.Store.GraphRoot}}' 2>/dev/null
        return $status
    end

    # ---------- debug ----------
    if test "$cmd" = debug
        echo "vault           = '$vault'"
        echo "luks_file       = '$luks_file'"
        echo "mapper_name     = '$mapper_name'"
        echo "graphroot       = '$graphroot'"
        echo "enc_home        = '$enc_home'"
        echo "box_name        = '$box_name'"
        echo "image           = '$image'"
        echo "container_home  = '$container_home'"
        echo "uid:gid         = '$uid:$gid'"
        echo "runtime_dir     = '$runtime_dir'"
        if set -q WAYLAND_DISPLAY
            echo "WAYLAND_DISPLAY = '$WAYLAND_DISPLAY'"
        else
            echo "WAYLAND_DISPLAY = <unset>"
        end
        if set -q DISPLAY
            echo "DISPLAY         = '$DISPLAY'"
        else
            echo "DISPLAY         = <unset>"
        end
        echo

        echo "== vault mountpoint =="
        mountpoint "$vault"
        echo "status=$status"
        echo

        echo "== mapper exists =="
        test -e "/dev/mapper/$mapper_name"
        echo "/dev/mapper/$mapper_name exists? status=$status"
        echo

        echo "== /dev/mapper =="
        ls /dev/mapper 2>/dev/null
        echo

        echo "== podman graphRoot =="
        podman info --format '{{.Store.GraphRoot}}' 2>/dev/null
        echo "status=$status"
        echo

        echo "== GUI sockets (host) =="
        test -S "$runtime_dir/$WAYLAND_DISPLAY"; and echo "wayland socket exists: $runtime_dir/$WAYLAND_DISPLAY"; or echo "wayland socket missing"
        test -S "$runtime_dir/pulse/native"; and echo "pulse socket exists:   $runtime_dir/pulse/native"; or echo "pulse socket missing"
        test -S "$runtime_dir/pipewire-0"; and echo "pipewire socket exists:$runtime_dir/pipewire-0"; or echo "pipewire socket missing"
        test -S "$runtime_dir/bus"; and echo "dbus socket exists:    $runtime_dir/bus"; or echo "dbus socket missing"
        return 0
    end

    # ---------- status ----------
    if contains -- "$cmd" status st
        echo "=== Config ==="
        echo "Vault      : $vault"
        echo "LUKS file  : $luks_file"
        echo "Mapper     : $mapper_name"
        echo "GraphRoot  : $graphroot"
        echo "Box        : $box_name"
        echo "Image      : $image"
        echo "Enc HOME   : $enc_home -> $container_home"

        echo
        echo "=== Vault ==="
        if test -e "/dev/mapper/$mapper_name"
            echo "Mapper     : open (/dev/mapper/$mapper_name)"
        else
            echo "Mapper     : closed"
        end
        if mountpoint -q "$vault"
            echo "Mount      : mounted at $vault"
        else
            echo "Mount      : not mounted"
        end

        echo
        echo "=== Podman ==="
        podman info --format 'graphRoot={{.Store.GraphRoot}} runRoot={{.Store.RunRoot}}' 2>/dev/null
        or echo "Podman info unavailable"

        echo
        echo "=== Container ==="
        if podman inspect "$box_name" >/dev/null 2>&1
            echo "Exists      : yes"
            podman inspect --format 'Running={{.State.Running}} Status={{.State.Status}}' "$box_name" 2>/dev/null
        else
            echo "Exists      : no"
        end
        return 0
    end

    # ---------- create / recreate ----------
    if contains -- "$cmd" create recreate rebuild
        if not mountpoint -q "$vault"
            kali open; or return 1
        end

        mkdir -p "$enc_home" "$graphroot"

        set -l current_graphroot (podman info --format '{{.Store.GraphRoot}}' 2>/dev/null)
        if test $status -ne 0
            echo "podman info failed" >&2
            return 1
        end
        if test "$current_graphroot" != "$graphroot"
            echo "Podman graphroot mismatch" >&2
            echo "Expected: $graphroot" >&2
            echo "Actual:   $current_graphroot" >&2
            echo "Run: kali init-storage" >&2
            return 1
        end

        if test "$cmd" != create
            if podman inspect "$box_name" >/dev/null 2>&1
                set -l running_state (podman inspect --format '{{.State.Running}}' "$box_name" 2>/dev/null)
                if test "$running_state" = "true"
                    echo "Stopping existing container..."
                    podman stop "$box_name" >/dev/null; or return 1
                end
                echo "Removing existing container..."
                podman rm "$box_name" >/dev/null; or return 1
            end
        else
            if podman inspect "$box_name" >/dev/null 2>&1
                echo "Container '$box_name' already exists (use: kali recreate)" >&2
                return 1
            end
        end

        echo "Pulling image (if needed): $image"
        podman pull "$image"; or return 1

        # Build create args (fish array)
        set -l args
        set -a args create
        set -a args --name "$box_name"
        set -a args --hostname "$box_name"
        set -a args --userns=keep-id
        set -a args --user "$uid:$gid"
        set -a args --group-add keep-groups
        set -a args --security-opt label=disable
        set -a args -e HOME="$container_home"
        set -a args -w "$container_home"
	set -a args -e HOME="$container_home"
set -a args -e XDG_CONFIG_HOME="$container_home/.config"
set -a args -e XDG_CACHE_HOME="$container_home/.cache"
set -a args -e XDG_DATA_HOME="$container_home/.local/share"
set -a args -e XDG_STATE_HOME="$container_home/.local/state"

        # Core encrypted mounts (no host home bind)
        set -a args -v "$enc_home:$container_home:rw"
        set -a args -v "$vault:/vault:rw"

# Optional host config passthroughs (read-only)
# Keep fish_variables container-local (DO NOT mount it) to avoid:
# - read-only fs errors
# - fish version incompatibility with host-saved universal vars/themes
mkdir -p "$enc_home/.config/fish"
mkdir -p "$enc_home/.config/fish/conf.d"
mkdir -p "$enc_home/.config/fish/functions"
mkdir -p "$enc_home/.config/fish/completions"

# Mount only selected fish config pieces, not the whole directory
if test -f "$HOME/.config/fish/config.fish"
    set -a args -v "$HOME/.config/fish/config.fish:$container_home/.config/fish/config.fish:ro"
end

if test -d "$HOME/.config/fish/conf.d"
    set -a args -v "$HOME/.config/fish/conf.d:$container_home/.config/fish/conf.d:ro"
end

if test -d "$HOME/.config/fish/functions"
    set -a args -v "$HOME/.config/fish/functions:$container_home/.config/fish/functions:ro"
end

if test -d "$HOME/.config/fish/completions"
    set -a args -v "$HOME/.config/fish/completions:$container_home/.config/fish/completions:ro"
end

# starship config (single file)
if test -f "$HOME/.config/starship.toml"
    mkdir -p "$enc_home/.config"
    set -a args -v "$HOME/.config/starship.toml:$container_home/.config/starship.toml:ro"
end

        # GPU (Intel iGPU via /dev/dri)
        if test -d /dev/dri
            set -a args --device /dev/dri
        end

        # Wayland socket
        if set -q WAYLAND_DISPLAY; and test -n "$WAYLAND_DISPLAY"; and test -S "$runtime_dir/$WAYLAND_DISPLAY"
            set -a args -e XDG_RUNTIME_DIR="/run/user/$uid"
            set -a args -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
            set -a args -v "$runtime_dir/$WAYLAND_DISPLAY:/run/user/$uid/$WAYLAND_DISPLAY"
        end

        # X11 / XWayland fallback
        if set -q DISPLAY; and test -n "$DISPLAY"; and test -d /tmp/.X11-unix
            set -a args -e DISPLAY="$DISPLAY"
            set -a args -v "/tmp/.X11-unix:/tmp/.X11-unix:rw"
        end

        # Session DBus (helps many GUI apps/portals)
        if test -S "$runtime_dir/bus"
            set -a args -e DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
            set -a args -v "$runtime_dir/bus:/run/user/$uid/bus"
        end

        # Audio (Pulse compatibility socket, usually backed by PipeWire on host)
        if test -S "$runtime_dir/pulse/native"
            set -a args -e PULSE_SERVER="unix:/run/user/$uid/pulse/native"
            set -a args -v "$runtime_dir/pulse/native:/run/user/$uid/pulse/native"
        end

        # PipeWire native socket (optional, some apps use it directly)
        if test -S "$runtime_dir/pipewire-0"
            set -a args -v "$runtime_dir/pipewire-0:/run/user/$uid/pipewire-0"
        end

        # Keep container alive; we'll exec into it
        set -a args "$image"
        set -a args sh -lc "mkdir -p '$container_home' && trap : TERM INT; sleep infinity & wait"

        echo "Creating container '$box_name'..."
        podman $args; or return 1

        echo "Starting container '$box_name'..."
        podman start "$box_name" >/dev/null; or return 1

        echo "Created + started."
        echo "Use: kali a"
        return 0
    end

    # ---------- destroy ----------
    if test "$cmd" = destroy
        if not podman inspect "$box_name" >/dev/null 2>&1
            echo "Container '$box_name' does not exist"
            return 0
        end

        set -l running_state (podman inspect --format '{{.State.Running}}' "$box_name" 2>/dev/null)
        if test "$running_state" = "true"
            echo "Stopping container..."
            podman stop "$box_name" >/dev/null; or return 1
        end

        echo "Removing container..."
        podman rm "$box_name" >/dev/null; or return 1
        echo "Removed '$box_name'"
        return 0
    end

    # ---------- start / stop ----------
    if test "$cmd" = start
        if not mountpoint -q "$vault"
            kali open; or return 1
        end
        if not podman inspect "$box_name" >/dev/null 2>&1
            echo "Container '$box_name' does not exist (run: kali create)" >&2
            return 1
        end
        podman start "$box_name" >/dev/null; or return 1
        echo "Started $box_name"
        return 0
    end

    if test "$cmd" = stop
        if not podman inspect "$box_name" >/dev/null 2>&1
            echo "Container '$box_name' does not exist"
            return 0
        end
        podman stop "$box_name" >/dev/null; or return 1
        echo "Stopped $box_name"
        return 0
    end

    # ---------- attach / run / spawn / where ----------
    if contains -- "$cmd" a attach r run s spawn where
        if not mountpoint -q "$vault"
            kali open; or return 1
        end

        set -l current_graphroot (podman info --format '{{.Store.GraphRoot}}' 2>/dev/null)
        if test $status -ne 0
            echo "podman info failed" >&2
            return 1
        end
        if test "$current_graphroot" != "$graphroot"
            echo "Podman graphroot mismatch" >&2
            echo "Expected: $graphroot" >&2
            echo "Actual:   $current_graphroot" >&2
            echo "Run: kali init-storage" >&2
            return 1
        end

        if not podman inspect "$box_name" >/dev/null 2>&1
            echo "Container '$box_name' does not exist (run: kali create)" >&2
            return 1
        end

        set -l running_state (podman inspect --format '{{.State.Running}}' "$box_name" 2>/dev/null)
        if test "$running_state" != "true"
            podman start "$box_name" >/dev/null; or return 1
        end

        # Refresh env per exec (important if session vars changed)
        set -l execenv
        if set -q WAYLAND_DISPLAY; and test -n "$WAYLAND_DISPLAY"
            set -a execenv -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
        end
        if set -q DISPLAY; and test -n "$DISPLAY"
            set -a execenv -e DISPLAY="$DISPLAY"
        end
        set -a execenv -e HOME="$container_home"
        set -a execenv -e XDG_RUNTIME_DIR="/run/user/$uid"
        set -a execenv -e CONTAINER_ID="kali"
	if test -S "$runtime_dir/bus"
            set -a execenv -e DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
        end
        if test -S "$runtime_dir/pulse/native"
            set -a execenv -e PULSE_SERVER="unix:/run/user/$uid/pulse/native"
        end

        switch "$cmd"
            case a attach
                podman exec -it $execenv -w "$container_home" "$box_name" sh -lc '
                    cd "$HOME"
                    if command -v fish >/dev/null 2>&1; then
                        exec fish -l
                    elif command -v bash >/dev/null 2>&1; then
                        exec bash -l
                    else
                        exec sh
                    fi
                '
                return $status

            case r run
                if test (count $argv) -eq 0
                    echo "Usage: kali run <cmd> [args...]" >&2
                    return 1
                end
                podman exec -it $execenv -w "$container_home" "$box_name" $argv
                return $status

	    case s spawn
    		if test (count $argv) -eq 0
    		    echo "Usage: kali spawn <app> [args...]" >&2
    		    return 1
    		end

		# Detached launch: returns immediately, no stdout/stderr in your terminal.
		# Note: success here only means the process was started, not that the app stayed alive.
    	    	podman exec -d $execenv -w "$container_home" "$box_name" $argv >/dev/null 2>&1
    		return $status
            case where
                podman exec -it $execenv -w "$container_home" "$box_name" sh -lc '
                    echo "USER=$USER"
                    echo "HOME=$HOME"
                    echo "PWD=$(pwd)"
                    id
                    echo
                    echo "--- mounts (relevant) ---"
                    mount | grep -E "/home|/vault|/run/user|/tmp/.X11-unix" || true
                    echo
                    echo "--- home listing ---"
                    ls -la "$HOME" | head -n 40
                '
                return $status
        end
    end

    echo "Unknown subcommand: $cmd" >&2
    echo
    kali help
    return 1
end
