# 🖊️ Set window title
precmd() {
  print -Pn "\e]2;%~\a"
}

# 📂 PATH - local binaries
export PATH="$PATH:$HOME/local/nvim/bin"
# Rust
export PATH="$HOME/.cargo/bin:$PATH"
# Locals
export PATH="/Users/stas/.local/bin:$PATH"

# 🎨 Start Oh My Posh
eval "$(oh-my-posh init zsh)"

# ⚙️ Autocomplete - start
autoload -Uz compinit
compinit

# 🧠 Better completition:
# - Case-insensitive
# - Colors
# - Cached
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion::complete:*' use-cache on
# ⁉️ You need to create folder ~/.zsh/cache
zstyle ':completion::complete:*' cache-path ~/.zsh/cache

# compdef gh
compdef _gh gh

# 🐙 completion for gh
__gh_debug()
{
    local file="$BASH_COMP_DEBUG_FILE"
    if [[ -n ${file} ]]; then
        echo "$*" >> "${file}"
    fi
}

_gh()
{
    local shellCompDirectiveError=1
    local shellCompDirectiveNoSpace=2
    local shellCompDirectiveNoFileComp=4
    local shellCompDirectiveFilterFileExt=8
    local shellCompDirectiveFilterDirs=16
    local shellCompDirectiveKeepOrder=32

    local lastParam lastChar flagPrefix requestComp out directive comp lastComp noSpace keepOrder
    local -a completions

    __gh_debug "\n========= starting completion logic =========="
    __gh_debug "CURRENT: ${CURRENT}, words[*]: ${words[*]}"

    # The user could have moved the cursor backwards on the command-line.
    # We need to trigger completion from the $CURRENT location, so we need
    # to truncate the command-line ($words) up to the $CURRENT location.
    # (We cannot use $CURSOR as its value does not work when a command is an alias.)
    words=("${=words[1,CURRENT]}")
    __gh_debug "Truncated words[*]: ${words[*]},"

    lastParam=${words[-1]}
    lastChar=${lastParam[-1]}
    __gh_debug "lastParam: ${lastParam}, lastChar: ${lastChar}"

    # For zsh, when completing a flag with an = (e.g., gh -n=<TAB>)
    # completions must be prefixed with the flag
    setopt local_options BASH_REMATCH
    if [[ "${lastParam}" =~ '-.*=' ]]; then
        # We are dealing with a flag with an =
        flagPrefix="-P ${BASH_REMATCH}"
    fi

    # Prepare the command to obtain completions
    requestComp="${words[1]} __complete ${words[2,-1]}"
    if [ "${lastChar}" = "" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go completion code.
        __gh_debug "Adding extra empty parameter"
        requestComp="${requestComp} \"\""
    fi

    __gh_debug "About to call: eval ${requestComp}"

    # Use eval to handle any environment variables and such
    out=$(eval ${requestComp} 2>/dev/null)
    __gh_debug "completion output: ${out}"

    # Extract the directive integer following a : from the last line
    local lastLine
    while IFS='\n' read -r line; do
        lastLine=${line}
    done < <(printf "%s\n" "${out[@]}")
    __gh_debug "last line: ${lastLine}"

    if [ "${lastLine[1]}" = : ]; then
        directive=${lastLine[2,-1]}
        # Remove the directive including the : and the newline
        local suffix
        (( suffix=${#lastLine}+2))
        out=${out[1,-$suffix]}
    else
        # There is no directive specified.  Leave $out as is.
        __gh_debug "No directive found.  Setting do default"
        directive=0
    fi

    __gh_debug "directive: ${directive}"
    __gh_debug "completions: ${out}"
    __gh_debug "flagPrefix: ${flagPrefix}"

    if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
        __gh_debug "Completion received error. Ignoring completions."
        return
    fi

    local activeHelpMarker="_activeHelp_ "
    local endIndex=${#activeHelpMarker}
    local startIndex=$((${#activeHelpMarker}+1))
    local hasActiveHelp=0
    while IFS='\n' read -r comp; do
        # Check if this is an activeHelp statement (i.e., prefixed with $activeHelpMarker)
        if [ "${comp[1,$endIndex]}" = "$activeHelpMarker" ];then
            __gh_debug "ActiveHelp found: $comp"
            comp="${comp[$startIndex,-1]}"
            if [ -n "$comp" ]; then
                compadd -x "${comp}"
                __gh_debug "ActiveHelp will need delimiter"
                hasActiveHelp=1
            fi

            continue
        fi

        if [ -n "$comp" ]; then
            # If requested, completions are returned with a description.
            # The description is preceded by a TAB character.
            # For zsh's _describe, we need to use a : instead of a TAB.
            # We first need to escape any : as part of the completion itself.
            comp=${comp//:/\\:}

            local tab="$(printf '\t')"
            comp=${comp//$tab/:}

            __gh_debug "Adding completion: ${comp}"
            completions+=${comp}
            lastComp=$comp
        fi
    done < <(printf "%s\n" "${out[@]}")

    # Add a delimiter after the activeHelp statements, but only if:
    # - there are completions following the activeHelp statements, or
    # - file completion will be performed (so there will be choices after the activeHelp)
    if [ $hasActiveHelp -eq 1 ]; then
        if [ ${#completions} -ne 0 ] || [ $((directive & shellCompDirectiveNoFileComp)) -eq 0 ]; then
            __gh_debug "Adding activeHelp delimiter"
            compadd -x "--"
            hasActiveHelp=0
        fi
    fi

    if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
        __gh_debug "Activating nospace."
        noSpace="-S ''"
    fi

    if [ $((directive & shellCompDirectiveKeepOrder)) -ne 0 ]; then
        __gh_debug "Activating keep order."
        keepOrder="-V"
    fi

    if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
        # File extension filtering
        local filteringCmd
        filteringCmd='_files'
        for filter in ${completions[@]}; do
            if [ ${filter[1]} != '*' ]; then
                # zsh requires a glob pattern to do file filtering
                filter="\*.$filter"
            fi
            filteringCmd+=" -g $filter"
        done
        filteringCmd+=" ${flagPrefix}"

        __gh_debug "File filtering command: $filteringCmd"
        _arguments '*:filename:'"$filteringCmd"
    elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
        # File completion for directories only
        local subdir
        subdir="${completions[1]}"
        if [ -n "$subdir" ]; then
            __gh_debug "Listing directories in $subdir"
            pushd "${subdir}" >/dev/null 2>&1
        else
            __gh_debug "Listing directories in ."
        fi

        local result
        _arguments '*:dirname:_files -/'" ${flagPrefix}"
        result=$?
        if [ -n "$subdir" ]; then
            popd >/dev/null 2>&1
        fi
        return $result
    else
        __gh_debug "Calling _describe"
        if eval _describe $keepOrder "completions" completions $flagPrefix $noSpace; then
            __gh_debug "_describe found some completions"

            # Return the success of having called _describe
            return 0
        else
            __gh_debug "_describe did not find completions."
            __gh_debug "Checking if we should do file completion."
            if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
                __gh_debug "deactivating file completion"

                # We must return an error code here to let zsh know that there were no
                # completions found by _describe; this is what will trigger other
                # matching algorithms to attempt to find completions.
                # For example zsh can match letters in the middle of words.
                return 1
            else
                # Perform file completion
                __gh_debug "Activating file completion"

                # We must return the result of this command, so it must be the
                # last command, or else we must store its result to return it.
                _arguments '*:filename:_files'" ${flagPrefix}"
            fi
        fi
    fi
}

# don't run the completion function when being source-ed or eval-ed
if [ "$funcstack[1]" = "_gh" ]; then
    _gh
fi

#compdef walrus

autoload -U is-at-least

_walrus() {
    typeset -A opt_args
    typeset -a _arguments_options
    local ret=1

    if is-at-least 5.2; then
        _arguments_options=(-s -S -C)
    else
        _arguments_options=(-s -C)
    fi

    local context curcontext="$curcontext" state line
    _arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_walrus_commands" \
"*::: :->walrus-service" \
&& ret=0
    case $state in
    (walrus-service)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:walrus-command-$line[1]:"
        case $line[1] in
            (json)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'::command_string -- The JSON-encoded args for the Walrus CLI; if not present, the args are read from stdin.:_default' \
&& ret=0
;;
(completion)
_arguments "${_arguments_options[@]}" : \
'--shell=[Shell type to generate completion script for the specified shell]:SHELL:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(store)
_arguments "${_arguments_options[@]}" : \
'--epochs=[The number of epochs the blob is stored for]:EPOCHS:_default' \
'--earliest-expiry-time=[The earliest time when the blob can expire, in RFC3339 format (e.g., "2024-03-20T15\:00\:00Z") or a more relaxed format (e.g., "2024-03-20 15\:00\:00")]:EARLIEST_EXPIRY_TIME:_default' \
'--end-epoch=[The end epoch for the blob]:END_EPOCH:_default' \
'--encoding-type=[The encoding type to use for encoding the files]:ENCODING_TYPE:_default' \
'--upload-relay=[Walrus Upload Relay URL to use for storing the blob/quilt]:UPLOAD_RELAY:_default' \
'--upload-mode=[Preset upload mode to tune network concurrency and bytes-in-flight]:UPLOAD_MODE:(conservative balanced aggressive)' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--dry-run[Perform a dry-run of the store without performing any actions on chain]' \
'--force[Do not check for the blob/quilt status before storing it]' \
'--ignore-resources[Ignore the storage resources owned by the wallet]' \
'(--permanent)--deletable[Mark the blob/quilt as deletable. Conflicts with \`--permanent\`]' \
'--permanent[Mark the blob/quilt as permanent]' \
'--share[Whether to put the blob/quilt into a shared object]' \
'--skip-tip-confirmation[Skip the tip confirmation prompt when using the upload relay]' \
'--internal-run[Internal flag to signal the process is running as a child for background uploads]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'*::files -- The files containing the blobs to be published to Walrus:_files' \
&& ret=0
;;
(store-quilt)
_arguments "${_arguments_options[@]}" : \
'*--paths=[Paths to files to include in the quilt]' \
'(--paths)*--blobs=[Blobs to include in the quilt, each blob is specified as a JSON string]' \
'--epochs=[The number of epochs the blob is stored for]:EPOCHS:_default' \
'--earliest-expiry-time=[The earliest time when the blob can expire, in RFC3339 format (e.g., "2024-03-20T15\:00\:00Z") or a more relaxed format (e.g., "2024-03-20 15\:00\:00")]:EARLIEST_EXPIRY_TIME:_default' \
'--end-epoch=[The end epoch for the blob]:END_EPOCH:_default' \
'--encoding-type=[The encoding type to use for encoding the files]:ENCODING_TYPE:_default' \
'--upload-relay=[Walrus Upload Relay URL to use for storing the blob/quilt]:UPLOAD_RELAY:_default' \
'--upload-mode=[Preset upload mode to tune network concurrency and bytes-in-flight]:UPLOAD_MODE:(conservative balanced aggressive)' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--dry-run[Perform a dry-run of the store without performing any actions on chain]' \
'--force[Do not check for the blob/quilt status before storing it]' \
'--ignore-resources[Ignore the storage resources owned by the wallet]' \
'(--permanent)--deletable[Mark the blob/quilt as deletable. Conflicts with \`--permanent\`]' \
'--permanent[Mark the blob/quilt as permanent]' \
'--share[Whether to put the blob/quilt into a shared object]' \
'--skip-tip-confirmation[Skip the tip confirmation prompt when using the upload relay]' \
'--internal-run[Internal flag to signal the process is running as a child for background uploads]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(read)
_arguments "${_arguments_options[@]}" : \
'--out=[The file path where to write the blob]:OUT:_files' \
'--rpc-url=[The URL of the Sui RPC node to use]:RPC_URL:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--strict-consistency-check[Whether to perform a strict consistency check]' \
'(--strict-consistency-check)--skip-consistency-check[Whether to skip consistency checks entirely]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
':blob_id -- The blob ID to be read:_default' \
&& ret=0
;;
(read-quilt)
_arguments "${_arguments_options[@]}" : \
'(--quilt-patch-ids)--quilt-id=[The quilt ID, which is the BlobID of the quilt]:QUILT_ID:_default' \
'(--tag --quilt-patch-ids)*--identifiers=[The identifiers to read from the quilt]:IDENTIFIERS:_default' \
'(--quilt-patch-ids)*--tag=[The tag key and value]:KEY:_default:KEY:_default' \
'*--quilt-patch-ids=[The quilt patch IDs]:QUILT_PATCH_IDS:_default' \
'--out=[The directory path where to write the quilt patches. The blobs are written to the directory with the same name as the identifier. The user-defined metadata of the quilt patches, including identifiers and tags are printed to the stdout]:OUT:_files' \
'--rpc-url=[The URL of the Sui RPC node to use]:RPC_URL:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(list-patches-in-quilt)
_arguments "${_arguments_options[@]}" : \
'--rpc-url=[The URL of the Sui RPC node to use]:RPC_URL:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
':quilt_id -- The quilt ID to be inspected:_default' \
&& ret=0
;;
(blob-status)
_arguments "${_arguments_options[@]}" : \
'--file=[The file containing the blob to be checked]:FILE:_files' \
'--blob-id=[The blob ID to be checked]:BLOB_ID:_default' \
'--timeout=[Timeout for status requests to storage nodes]:TIMEOUT:_default' \
'--encoding-type=[The encoding type to use for encoding the file]:ENCODING_TYPE:_default' \
'--rpc-url=[The URL of the Sui RPC node to use]:RPC_URL:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(info)
_arguments "${_arguments_options[@]}" : \
'--rpc-url=[The URL of the Sui RPC node to use]:RPC_URL:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_walrus__info_commands" \
"*::: :->info" \
&& ret=0

    case $state in
    (info)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:walrus-info-command-$line[1]:"
        case $line[1] in
            (all)
_arguments "${_arguments_options[@]}" : \
'--sort-by=[Field to sort by]:SORT_BY:((id\:"Sort by node ID"
name\:"Sort by node name"
url\:"Sort by node URL"))' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--desc[Sort in descending order]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(epoch)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(storage)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(size)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(price)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(bft)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(committee)
_arguments "${_arguments_options[@]}" : \
'--sort-by=[Field to sort by]:SORT_BY:((id\:"Sort by node ID"
name\:"Sort by node name"
url\:"Sort by node URL"))' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--desc[Sort in descending order]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" : \
":: :_walrus__info__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:walrus-info-help-command-$line[1]:"
        case $line[1] in
            (all)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(epoch)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(storage)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(size)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(price)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(bft)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(committee)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(health)
_arguments "${_arguments_options[@]}" : \
'--rpc-url=[The URL of the Sui RPC node to use]:RPC_URL:_default' \
'*--node-ids=[The IDs of the storage nodes to be selected]:NODE_IDS:_default' \
'*--node-urls=[The URLs of the storage nodes to be selected]:NODE_URLS:_default' \
'--sort-by=[Field to sort by]:SORT_BY:((status\:"Sort by node status"
id\:"Sort by node ID"
name\:"Sort by node name"
url\:"Sort by node URL"))' \
'--concurrent-requests=[Number of concurrent requests to send to the storage nodes]:CONCURRENT_REQUESTS:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--committee[Select all storage nodes in the current committee]' \
'--active-set[Select all storage nodes in the active set]' \
'--detail[Print detailed health information]' \
'--desc[Sort in descending order]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(blob-id)
_arguments "${_arguments_options[@]}" : \
'--n-shards=[The number of shards for which to compute the blob ID]:N_SHARDS:_default' \
'--rpc-url=[The URL of the Sui RPC node to use]:RPC_URL:_default' \
'--encoding-type=[The encoding type to use for computing the blob ID]:ENCODING_TYPE:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
':file -- The file containing the blob for which to compute the blob ID:_files' \
&& ret=0
;;
(convert-blob-id)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
':blob_id_decimal -- The decimal value to be converted to the Walrus blob ID:_default' \
&& ret=0
;;
(list-blobs)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--include-expired[The output list of blobs will include expired blobs]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(delete)
_arguments "${_arguments_options[@]}" : \
'*--files=[The file containing the blob to be deleted]' \
'*--blob-ids=[The blob ID to be deleted]:BLOB_IDS:_default' \
'*--object-ids=[The object ID of the blob object to be deleted]' \
'--encoding-type=[The encoding type to use for computing the blob ID]:ENCODING_TYPE:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--yes[Proceed to delete the blob without confirmation]' \
'--no-status-check[Disable checking the status of the blob after deletion]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(stake)
_arguments "${_arguments_options[@]}" : \
'*--node-ids=[The object ID of the storage node to stake with]:NODE_IDS:_default' \
'*--amounts=[The amount of FROST (smallest unit of WAL token) to stake with the storage node]:AMOUNTS:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(generate-sui-wallet)
_arguments "${_arguments_options[@]}" : \
'--path=[The path where the wallet configuration will be stored]:PATH:_files' \
'--sui-network=[Sui network for which the wallet is generated]:SUI_NETWORK:_default' \
'--faucet-timeout=[Timeout for the faucet call]:FAUCET_TIMEOUT:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--use-faucet[Whether to attempt to get SUI tokens from the faucet]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(get-wal)
_arguments "${_arguments_options[@]}" : \
'--exchange-id=[The object ID of the exchange to use]:EXCHANGE_ID:_default' \
'--amount=[The amount of MIST to exchange for WAL/FROST]:AMOUNT:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(burn-blobs)
_arguments "${_arguments_options[@]}" : \
'*--object-ids=[The object IDs of the Blob objects to burn]:OBJECT_IDS:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--all[Burn all the blob objects owned by the wallet]' \
'--all-expired[Burn all the expired blob objects owned by the wallet]' \
'--yes[Proceed to burn the blobs without confirmation]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(fund-shared-blob)
_arguments "${_arguments_options[@]}" : \
'--shared-blob-obj-id=[The object ID of the shared blob to fund]:SHARED_BLOB_OBJ_ID:_default' \
'--amount=[The amount of FROST (smallest unit of WAL token) to fund the shared blob with]:AMOUNT:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(extend)
_arguments "${_arguments_options[@]}" : \
'--blob-obj-id=[The object ID of the blob to extend]:BLOB_OBJ_ID:_default' \
'--epochs-extended=[The number of epochs to extend the blob for]:EPOCHS_EXTENDED:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--shared[If the blob_obj_id refers to a shared blob object, this flag must be present]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(share)
_arguments "${_arguments_options[@]}" : \
'--blob-obj-id=[The object ID of the (owned) blob to share]:BLOB_OBJ_ID:_default' \
'--amount=[If specified, share and directly fund the blob]:AMOUNT:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(get-blob-attribute)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
':blob_obj_id -- The object ID of the blob to get the attribute of:_default' \
&& ret=0
;;
(set-blob-attribute)
_arguments "${_arguments_options[@]}" : \
'*--attr=[The key-value pairs to set as attributes. Multiple pairs can be specified by repeating the flag. Example\: --attr "key1" "value1" --attr "key2" "value2"]:KEY:_default:KEY:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
':blob_obj_id -- The object ID of the blob to set the attribute of:_default' \
&& ret=0
;;
(remove-blob-attribute-fields)
_arguments "${_arguments_options[@]}" : \
'*--keys=[The keys to remove from the blob'\''s attribute. Multiple keys should be provided as separate arguments. Examples\: --keys "key1" "key2,with,commas" "key3 with spaces"]:KEYS:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
':blob_obj_id -- The object ID of the blob:_default' \
&& ret=0
;;
(remove-blob-attribute)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
':blob_obj_id -- The object ID of the blob:_default' \
&& ret=0
;;
(node-admin)
_arguments "${_arguments_options[@]}" : \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
":: :_walrus__node-admin_commands" \
"*::: :->node-admin" \
&& ret=0

    case $state in
    (node-admin)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:walrus-node-admin-command-$line[1]:"
        case $line[1] in
            (collect-commission)
_arguments "${_arguments_options[@]}" : \
'--node-id=[The ID of the node for which the operation should be performed]:NODE_ID:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(vote-for-upgrade)
_arguments "${_arguments_options[@]}" : \
'--node-id=[The ID of the node for which the operation should be performed]:NODE_ID:_default' \
'--upgrade-manager-object-id=[The upgrade manager object ID]:UPGRADE_MANAGER_OBJECT_ID:_default' \
'--package-path=[The path to the walrus package directory]:PACKAGE_PATH:_files' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(set-governance-authorized)
_arguments "${_arguments_options[@]}" : \
'--node-id=[The ID of the node for which the operation should be performed]:NODE_ID:_default' \
'--address=[Set an address as authorized entity]:ADDRESS:_default' \
'--object=[Set an object as capability to authorize operations]:OBJECT:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(set-commission-authorized)
_arguments "${_arguments_options[@]}" : \
'--node-id=[The ID of the node for which the operation should be performed]:NODE_ID:_default' \
'--address=[Set an address as authorized entity]:ADDRESS:_default' \
'--object=[Set an object as capability to authorize operations]:OBJECT:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(package-digest)
_arguments "${_arguments_options[@]}" : \
'--package-path=[The path to the package directory]:PACKAGE_PATH:_files' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" : \
":: :_walrus__node-admin__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:walrus-node-admin-help-command-$line[1]:"
        case $line[1] in
            (collect-commission)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(vote-for-upgrade)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(set-governance-authorized)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(set-commission-authorized)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(package-digest)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
;;
(pull-archive-blobs)
_arguments "${_arguments_options[@]}" : \
'--gcs-bucket=[The Google Cloud Storage bucket to pull from]:GCS_BUCKET:_default' \
'--prefix=[Optional object name prefix filter]:PREFIX:_default' \
'--backfill-dir=[The directory to pull into]:BACKFILL_DIR:_default' \
'--pulled-state=[Durable list of objects already pulled]:PULLED_STATE:_files' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(blob-backfill)
_arguments "${_arguments_options[@]}" : \
'--backfill-dir=[The subdirectory when blob-backfill can find blobs]:BACKFILL_DIR:_files' \
'--pushed-state=[The file where successfully pushed blob IDs will be stored]:PUSHED_STATE:_files' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
'*::node_ids -- The nodes to backfill with slivers and blob metadata:_default' \
&& ret=0
;;
(publisher)
_arguments "${_arguments_options[@]}" : \
'--bind-address=[The address to which to bind the service]:BIND_ADDRESS:_default' \
'-a+[Socket address on which the Prometheus server should export its metrics]:METRICS_ADDRESS:_default' \
'--metrics-address=[Socket address on which the Prometheus server should export its metrics]:METRICS_ADDRESS:_default' \
'--blocklist=[Path to a blocklist file containing a list (in YAML syntax) of blocked blob IDs]:BLOCKLIST:_files' \
'--max-body-size=[The maximum body size of PUT requests in KiB]:MAX_BODY_SIZE_KIB:_default' \
'--max-quilt-body-size=[The maximum body size of quilt PUT requests in KiB]:MAX_QUILT_BODY_SIZE_KIB:_default' \
'--publisher-max-buffer-size=[The maximum number of requests that can be buffered before the server starts rejecting new ones. (Note\: --max-buffer-size is deprecated, use --publisher-max-buffer-size)]:PUBLISHER_MAX_REQUEST_BUFFER_SIZE:_default' \
'--publisher-max-concurrent-requests=[The maximum number of requests the publisher can process concurrently. (Note\: --max-concurrent-requests is deprecated, use --publisher-max-concurrent-requests)]:PUBLISHER_MAX_CONCURRENT_REQUESTS:_default' \
'--n-clients=[The number of clients to use for the publisher]:N_CLIENTS:_default' \
'--refill-interval=[The interval of time between refilling the publisher'\''s sub-clients'\'' wallets]:REFILL_INTERVAL:_default' \
'--sub-wallets-dir=[The directory where the publisher will store the sub-wallets used for client multiplexing]:SUB_WALLETS_DIR:_files' \
'--gas-refill-amount=[The amount of MIST transferred at every refill]:GAS_REFILL_AMOUNT:_default' \
'--wal-refill-amount=[The amount of FROST transferred at every refill]:WAL_REFILL_AMOUNT:_default' \
'--sub-wallets-min-balance=[The minimum balance the sub-wallets should have]:SUB_WALLETS_MIN_BALANCE:_default' \
'--jwt-decode-secret=[If set, the publisher will verify the JWT token]:JWT_DECODE_SECRET:_default' \
'--jwt-algorithm=[If unset, the JWT authentication algorithm will be HMAC (HS256)]:JWT_ALGORITHM:_default' \
'--jwt-expiring-sec=[If set and greater than 0, the publisher will check if the JWT token is expired based on the "issued at" (\`iat\`) value]:JWT_EXPIRING_SEC:_default' \
'--jwt-cache-size=[The maximum number of elements the cache can hold]:MAX_SIZE:_default' \
'--jwt-cache-refresh-interval=[The interval at which the cache should check for expired elements]:REFRESH_INTERVAL:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--keep[Deprecated flag for backwards compatibility]' \
'--burn-after-store[If set, the publisher will burn the created Blob objects immediately]' \
'--jwt-verify-upload[If set, the publisher will verify that the requested upload matches the claims in the JWT]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(aggregator)
_arguments "${_arguments_options[@]}" : \
'--rpc-url=[The URL of the Sui RPC node to use]:RPC_URL:_default' \
'--bind-address=[The address to which to bind the service]:BIND_ADDRESS:_default' \
'-a+[Socket address on which the Prometheus server should export its metrics]:METRICS_ADDRESS:_default' \
'--metrics-address=[Socket address on which the Prometheus server should export its metrics]:METRICS_ADDRESS:_default' \
'--blocklist=[Path to a blocklist file containing a list (in YAML syntax) of blocked blob IDs]:BLOCKLIST:_files' \
'*--allowed-headers=[Allowed headers for the daemon]:ALLOWED_HEADERS:_default' \
'--max-blob-size=[The maximum blob size in bytes]:MAX_BLOB_SIZE:_default' \
'--aggregator-max-buffer-size=[The maximum number of requests that can be buffered before the server starts rejecting new ones. Note that this includes the number of requests that are being processed currently]:AGGREGATOR_MAX_REQUEST_BUFFER_SIZE:_default' \
'--aggregator-max-concurrent-requests=[The maximum number of requests the aggregator can process concurrently]:AGGREGATOR_MAX_CONCURRENT_REQUESTS:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--allow-quilt-patch-tags-in-response[Whether to allow quilt patch tags to be returned in the response headers. If true, the tags will be returned in the response headers, regardless of the allowed headers]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(daemon)
_arguments "${_arguments_options[@]}" : \
'--bind-address=[The address to which to bind the service]:BIND_ADDRESS:_default' \
'-a+[Socket address on which the Prometheus server should export its metrics]:METRICS_ADDRESS:_default' \
'--metrics-address=[Socket address on which the Prometheus server should export its metrics]:METRICS_ADDRESS:_default' \
'--blocklist=[Path to a blocklist file containing a list (in YAML syntax) of blocked blob IDs]:BLOCKLIST:_files' \
'--max-body-size=[The maximum body size of PUT requests in KiB]:MAX_BODY_SIZE_KIB:_default' \
'--max-quilt-body-size=[The maximum body size of quilt PUT requests in KiB]:MAX_QUILT_BODY_SIZE_KIB:_default' \
'--publisher-max-buffer-size=[The maximum number of requests that can be buffered before the server starts rejecting new ones. (Note\: --max-buffer-size is deprecated, use --publisher-max-buffer-size)]:PUBLISHER_MAX_REQUEST_BUFFER_SIZE:_default' \
'--publisher-max-concurrent-requests=[The maximum number of requests the publisher can process concurrently. (Note\: --max-concurrent-requests is deprecated, use --publisher-max-concurrent-requests)]:PUBLISHER_MAX_CONCURRENT_REQUESTS:_default' \
'--n-clients=[The number of clients to use for the publisher]:N_CLIENTS:_default' \
'--refill-interval=[The interval of time between refilling the publisher'\''s sub-clients'\'' wallets]:REFILL_INTERVAL:_default' \
'--sub-wallets-dir=[The directory where the publisher will store the sub-wallets used for client multiplexing]:SUB_WALLETS_DIR:_files' \
'--gas-refill-amount=[The amount of MIST transferred at every refill]:GAS_REFILL_AMOUNT:_default' \
'--wal-refill-amount=[The amount of FROST transferred at every refill]:WAL_REFILL_AMOUNT:_default' \
'--sub-wallets-min-balance=[The minimum balance the sub-wallets should have]:SUB_WALLETS_MIN_BALANCE:_default' \
'--jwt-decode-secret=[If set, the publisher will verify the JWT token]:JWT_DECODE_SECRET:_default' \
'--jwt-algorithm=[If unset, the JWT authentication algorithm will be HMAC (HS256)]:JWT_ALGORITHM:_default' \
'--jwt-expiring-sec=[If set and greater than 0, the publisher will check if the JWT token is expired based on the "issued at" (\`iat\`) value]:JWT_EXPIRING_SEC:_default' \
'--jwt-cache-size=[The maximum number of elements the cache can hold]:MAX_SIZE:_default' \
'--jwt-cache-refresh-interval=[The interval at which the cache should check for expired elements]:REFRESH_INTERVAL:_default' \
'*--allowed-headers=[Allowed headers for the daemon]:ALLOWED_HEADERS:_default' \
'--max-blob-size=[The maximum blob size in bytes]:MAX_BLOB_SIZE:_default' \
'--aggregator-max-buffer-size=[The maximum number of requests that can be buffered before the server starts rejecting new ones. Note that this includes the number of requests that are being processed currently]:AGGREGATOR_MAX_REQUEST_BUFFER_SIZE:_default' \
'--aggregator-max-concurrent-requests=[The maximum number of requests the aggregator can process concurrently]:AGGREGATOR_MAX_CONCURRENT_REQUESTS:_default' \
'--config=[The path to the Walrus configuration file.]:CONFIG:_files' \
'--context=[The configuration context to use for the client, if omitted the default_context is used]:CONTEXT:_default' \
'--wallet=[The path to the Sui wallet configuration file.]:WALLET:_files' \
'--gas-budget=[The gas budget for transactions]:GAS_BUDGET:_default' \
'--trace-cli=[Enable tracing output for the CLI, possible options are '\''otlp'\'' and '\''file=path'\'']:TRACE_CLI:_default' \
'--keep[Deprecated flag for backwards compatibility]' \
'--burn-after-store[If set, the publisher will burn the created Blob objects immediately]' \
'--jwt-verify-upload[If set, the publisher will verify that the requested upload matches the claims in the JWT]' \
'--allow-quilt-patch-tags-in-response[Whether to allow quilt patch tags to be returned in the response headers. If true, the tags will be returned in the response headers, regardless of the allowed headers]' \
'--json[Write output as JSON]' \
'-h[Print help (see more with '\''--help'\'')]' \
'--help[Print help (see more with '\''--help'\'')]' \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" : \
":: :_walrus__help_commands" \
"*::: :->help" \
&& ret=0

    case $state in
    (help)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:walrus-help-command-$line[1]:"
        case $line[1] in
            (json)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(completion)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(store)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(store-quilt)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(read)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(read-quilt)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(list-patches-in-quilt)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(blob-status)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(info)
_arguments "${_arguments_options[@]}" : \
":: :_walrus__help__info_commands" \
"*::: :->info" \
&& ret=0

    case $state in
    (info)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:walrus-help-info-command-$line[1]:"
        case $line[1] in
            (all)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(epoch)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(storage)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(size)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(price)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(bft)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(committee)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
        esac
    ;;
esac
;;
(health)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(blob-id)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(convert-blob-id)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(list-blobs)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(delete)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(stake)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(generate-sui-wallet)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(get-wal)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(burn-blobs)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(fund-shared-blob)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(extend)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(share)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(get-blob-attribute)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(set-blob-attribute)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(remove-blob-attribute-fields)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(remove-blob-attribute)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(node-admin)
_arguments "${_arguments_options[@]}" : \
":: :_walrus__help__node-admin_commands" \
"*::: :->node-admin" \
&& ret=0

    case $state in
    (node-admin)
        words=($line[1] "${words[@]}")
        (( CURRENT += 1 ))
        curcontext="${curcontext%:*:*}:walrus-help-node-admin-command-$line[1]:"
        case $line[1] in
            (collect-commission)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(vote-for-upgrade)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(set-governance-authorized)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(set-commission-authorized)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(package-digest)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
        esac
    ;;
esac
;;
(pull-archive-blobs)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(blob-backfill)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(publisher)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(aggregator)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(daemon)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
(help)
_arguments "${_arguments_options[@]}" : \
&& ret=0
;;
        esac
    ;;
esac
;;
        esac
    ;;
esac
}

(( $+functions[_walrus_commands] )) ||
_walrus_commands() {
    local commands; commands=(
'json:Run the client by specifying the arguments in a JSON string; CLI options are ignored' \
'completion:Generate autocompletion script' \
'store:Store a new blob into Walrus' \
'store-quilt:Store files as a quilt' \
'read:Read a blob from Walrus, given the blob ID' \
'read-quilt:Read quilt patches (blobs) from Walrus' \
'list-patches-in-quilt:List the blobs in a quilt' \
'blob-status:Get the status of a blob' \
'info:Print information about the Walrus storage system this client is connected to. Several subcommands are available to print different information' \
'health:Print health information for one or multiple storage nodes' \
'blob-id:Encode the specified file to obtain its blob ID' \
'convert-blob-id:Convert a decimal value to the Walrus blob ID (using URL-safe base64 encoding)' \
'list-blobs:List all registered blobs for the current wallet' \
'delete:Delete a blob from Walrus' \
'stake:Stake with storage node' \
'generate-sui-wallet:Generates a new Sui wallet' \
'get-wal:Exchange SUI for WAL through the configured exchange. This command is only available on Testnet' \
'burn-blobs:Burns one or more owned Blob object on Sui' \
'fund-shared-blob:Fund a shared blob' \
'extend:Extend an owned or shared blob' \
'share:Share a blob' \
'get-blob-attribute:Get the attribute of a blob' \
'set-blob-attribute:Set the attribute of a blob' \
'remove-blob-attribute-fields:Remove a key-value pair from a blob'\''s attribute' \
'remove-blob-attribute:Remove the attribute dynamic field from a blob' \
'node-admin:Administration subcommands for storage node operators' \
'pull-archive-blobs:Pull all blobs (filtered by optional prefix specifier) from Google Cloud Storage down into the specified backfill_dir' \
'blob-backfill:Upload blob slivers and metadata from a specified directory to the listed storage nodes' \
'publisher:Run a publisher service at the provided network address' \
'aggregator:Run an aggregator service at the provided network address' \
'daemon:Run a client daemon at the provided network address, combining the functionality of an aggregator and a publisher' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'walrus commands' commands "$@"
}
(( $+functions[_walrus__aggregator_commands] )) ||
_walrus__aggregator_commands() {
    local commands; commands=()
    _describe -t commands 'walrus aggregator commands' commands "$@"
}
(( $+functions[_walrus__blob-backfill_commands] )) ||
_walrus__blob-backfill_commands() {
    local commands; commands=()
    _describe -t commands 'walrus blob-backfill commands' commands "$@"
}
(( $+functions[_walrus__blob-id_commands] )) ||
_walrus__blob-id_commands() {
    local commands; commands=()
    _describe -t commands 'walrus blob-id commands' commands "$@"
}
(( $+functions[_walrus__blob-status_commands] )) ||
_walrus__blob-status_commands() {
    local commands; commands=()
    _describe -t commands 'walrus blob-status commands' commands "$@"
}
(( $+functions[_walrus__burn-blobs_commands] )) ||
_walrus__burn-blobs_commands() {
    local commands; commands=()
    _describe -t commands 'walrus burn-blobs commands' commands "$@"
}
(( $+functions[_walrus__completion_commands] )) ||
_walrus__completion_commands() {
    local commands; commands=()
    _describe -t commands 'walrus completion commands' commands "$@"
}
(( $+functions[_walrus__convert-blob-id_commands] )) ||
_walrus__convert-blob-id_commands() {
    local commands; commands=()
    _describe -t commands 'walrus convert-blob-id commands' commands "$@"
}
(( $+functions[_walrus__daemon_commands] )) ||
_walrus__daemon_commands() {
    local commands; commands=()
    _describe -t commands 'walrus daemon commands' commands "$@"
}
(( $+functions[_walrus__delete_commands] )) ||
_walrus__delete_commands() {
    local commands; commands=()
    _describe -t commands 'walrus delete commands' commands "$@"
}
(( $+functions[_walrus__extend_commands] )) ||
_walrus__extend_commands() {
    local commands; commands=()
    _describe -t commands 'walrus extend commands' commands "$@"
}
(( $+functions[_walrus__fund-shared-blob_commands] )) ||
_walrus__fund-shared-blob_commands() {
    local commands; commands=()
    _describe -t commands 'walrus fund-shared-blob commands' commands "$@"
}
(( $+functions[_walrus__generate-sui-wallet_commands] )) ||
_walrus__generate-sui-wallet_commands() {
    local commands; commands=()
    _describe -t commands 'walrus generate-sui-wallet commands' commands "$@"
}
(( $+functions[_walrus__get-blob-attribute_commands] )) ||
_walrus__get-blob-attribute_commands() {
    local commands; commands=()
    _describe -t commands 'walrus get-blob-attribute commands' commands "$@"
}
(( $+functions[_walrus__get-wal_commands] )) ||
_walrus__get-wal_commands() {
    local commands; commands=()
    _describe -t commands 'walrus get-wal commands' commands "$@"
}
(( $+functions[_walrus__health_commands] )) ||
_walrus__health_commands() {
    local commands; commands=()
    _describe -t commands 'walrus health commands' commands "$@"
}
(( $+functions[_walrus__help_commands] )) ||
_walrus__help_commands() {
    local commands; commands=(
'json:Run the client by specifying the arguments in a JSON string; CLI options are ignored' \
'completion:Generate autocompletion script' \
'store:Store a new blob into Walrus' \
'store-quilt:Store files as a quilt' \
'read:Read a blob from Walrus, given the blob ID' \
'read-quilt:Read quilt patches (blobs) from Walrus' \
'list-patches-in-quilt:List the blobs in a quilt' \
'blob-status:Get the status of a blob' \
'info:Print information about the Walrus storage system this client is connected to. Several subcommands are available to print different information' \
'health:Print health information for one or multiple storage nodes' \
'blob-id:Encode the specified file to obtain its blob ID' \
'convert-blob-id:Convert a decimal value to the Walrus blob ID (using URL-safe base64 encoding)' \
'list-blobs:List all registered blobs for the current wallet' \
'delete:Delete a blob from Walrus' \
'stake:Stake with storage node' \
'generate-sui-wallet:Generates a new Sui wallet' \
'get-wal:Exchange SUI for WAL through the configured exchange. This command is only available on Testnet' \
'burn-blobs:Burns one or more owned Blob object on Sui' \
'fund-shared-blob:Fund a shared blob' \
'extend:Extend an owned or shared blob' \
'share:Share a blob' \
'get-blob-attribute:Get the attribute of a blob' \
'set-blob-attribute:Set the attribute of a blob' \
'remove-blob-attribute-fields:Remove a key-value pair from a blob'\''s attribute' \
'remove-blob-attribute:Remove the attribute dynamic field from a blob' \
'node-admin:Administration subcommands for storage node operators' \
'pull-archive-blobs:Pull all blobs (filtered by optional prefix specifier) from Google Cloud Storage down into the specified backfill_dir' \
'blob-backfill:Upload blob slivers and metadata from a specified directory to the listed storage nodes' \
'publisher:Run a publisher service at the provided network address' \
'aggregator:Run an aggregator service at the provided network address' \
'daemon:Run a client daemon at the provided network address, combining the functionality of an aggregator and a publisher' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'walrus help commands' commands "$@"
}
(( $+functions[_walrus__help__aggregator_commands] )) ||
_walrus__help__aggregator_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help aggregator commands' commands "$@"
}
(( $+functions[_walrus__help__blob-backfill_commands] )) ||
_walrus__help__blob-backfill_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help blob-backfill commands' commands "$@"
}
(( $+functions[_walrus__help__blob-id_commands] )) ||
_walrus__help__blob-id_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help blob-id commands' commands "$@"
}
(( $+functions[_walrus__help__blob-status_commands] )) ||
_walrus__help__blob-status_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help blob-status commands' commands "$@"
}
(( $+functions[_walrus__help__burn-blobs_commands] )) ||
_walrus__help__burn-blobs_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help burn-blobs commands' commands "$@"
}
(( $+functions[_walrus__help__completion_commands] )) ||
_walrus__help__completion_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help completion commands' commands "$@"
}
(( $+functions[_walrus__help__convert-blob-id_commands] )) ||
_walrus__help__convert-blob-id_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help convert-blob-id commands' commands "$@"
}
(( $+functions[_walrus__help__daemon_commands] )) ||
_walrus__help__daemon_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help daemon commands' commands "$@"
}
(( $+functions[_walrus__help__delete_commands] )) ||
_walrus__help__delete_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help delete commands' commands "$@"
}
(( $+functions[_walrus__help__extend_commands] )) ||
_walrus__help__extend_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help extend commands' commands "$@"
}
(( $+functions[_walrus__help__fund-shared-blob_commands] )) ||
_walrus__help__fund-shared-blob_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help fund-shared-blob commands' commands "$@"
}
(( $+functions[_walrus__help__generate-sui-wallet_commands] )) ||
_walrus__help__generate-sui-wallet_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help generate-sui-wallet commands' commands "$@"
}
(( $+functions[_walrus__help__get-blob-attribute_commands] )) ||
_walrus__help__get-blob-attribute_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help get-blob-attribute commands' commands "$@"
}
(( $+functions[_walrus__help__get-wal_commands] )) ||
_walrus__help__get-wal_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help get-wal commands' commands "$@"
}
(( $+functions[_walrus__help__health_commands] )) ||
_walrus__help__health_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help health commands' commands "$@"
}
(( $+functions[_walrus__help__help_commands] )) ||
_walrus__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help help commands' commands "$@"
}
(( $+functions[_walrus__help__info_commands] )) ||
_walrus__help__info_commands() {
    local commands; commands=(
'all:Print all information listed below' \
'epoch:Print epoch information' \
'storage:Print storage information' \
'size:Print size information' \
'price:Print price information' \
'bft:Print byzantine fault tolerance (BFT) information' \
'committee:Print committee information' \
    )
    _describe -t commands 'walrus help info commands' commands "$@"
}
(( $+functions[_walrus__help__info__all_commands] )) ||
_walrus__help__info__all_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help info all commands' commands "$@"
}
(( $+functions[_walrus__help__info__bft_commands] )) ||
_walrus__help__info__bft_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help info bft commands' commands "$@"
}
(( $+functions[_walrus__help__info__committee_commands] )) ||
_walrus__help__info__committee_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help info committee commands' commands "$@"
}
(( $+functions[_walrus__help__info__epoch_commands] )) ||
_walrus__help__info__epoch_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help info epoch commands' commands "$@"
}
(( $+functions[_walrus__help__info__price_commands] )) ||
_walrus__help__info__price_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help info price commands' commands "$@"
}
(( $+functions[_walrus__help__info__size_commands] )) ||
_walrus__help__info__size_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help info size commands' commands "$@"
}
(( $+functions[_walrus__help__info__storage_commands] )) ||
_walrus__help__info__storage_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help info storage commands' commands "$@"
}
(( $+functions[_walrus__help__json_commands] )) ||
_walrus__help__json_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help json commands' commands "$@"
}
(( $+functions[_walrus__help__list-blobs_commands] )) ||
_walrus__help__list-blobs_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help list-blobs commands' commands "$@"
}
(( $+functions[_walrus__help__list-patches-in-quilt_commands] )) ||
_walrus__help__list-patches-in-quilt_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help list-patches-in-quilt commands' commands "$@"
}
(( $+functions[_walrus__help__node-admin_commands] )) ||
_walrus__help__node-admin_commands() {
    local commands; commands=(
'collect-commission:Collect the commission' \
'vote-for-upgrade:Vote for a contract upgrade' \
'set-governance-authorized:Set the authorized entity for governance operations' \
'set-commission-authorized:Set the authorized entity for commission operations' \
'package-digest:Outputs the package digest of a sui package' \
    )
    _describe -t commands 'walrus help node-admin commands' commands "$@"
}
(( $+functions[_walrus__help__node-admin__collect-commission_commands] )) ||
_walrus__help__node-admin__collect-commission_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help node-admin collect-commission commands' commands "$@"
}
(( $+functions[_walrus__help__node-admin__package-digest_commands] )) ||
_walrus__help__node-admin__package-digest_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help node-admin package-digest commands' commands "$@"
}
(( $+functions[_walrus__help__node-admin__set-commission-authorized_commands] )) ||
_walrus__help__node-admin__set-commission-authorized_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help node-admin set-commission-authorized commands' commands "$@"
}
(( $+functions[_walrus__help__node-admin__set-governance-authorized_commands] )) ||
_walrus__help__node-admin__set-governance-authorized_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help node-admin set-governance-authorized commands' commands "$@"
}
(( $+functions[_walrus__help__node-admin__vote-for-upgrade_commands] )) ||
_walrus__help__node-admin__vote-for-upgrade_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help node-admin vote-for-upgrade commands' commands "$@"
}
(( $+functions[_walrus__help__publisher_commands] )) ||
_walrus__help__publisher_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help publisher commands' commands "$@"
}
(( $+functions[_walrus__help__pull-archive-blobs_commands] )) ||
_walrus__help__pull-archive-blobs_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help pull-archive-blobs commands' commands "$@"
}
(( $+functions[_walrus__help__read_commands] )) ||
_walrus__help__read_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help read commands' commands "$@"
}
(( $+functions[_walrus__help__read-quilt_commands] )) ||
_walrus__help__read-quilt_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help read-quilt commands' commands "$@"
}
(( $+functions[_walrus__help__remove-blob-attribute_commands] )) ||
_walrus__help__remove-blob-attribute_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help remove-blob-attribute commands' commands "$@"
}
(( $+functions[_walrus__help__remove-blob-attribute-fields_commands] )) ||
_walrus__help__remove-blob-attribute-fields_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help remove-blob-attribute-fields commands' commands "$@"
}
(( $+functions[_walrus__help__set-blob-attribute_commands] )) ||
_walrus__help__set-blob-attribute_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help set-blob-attribute commands' commands "$@"
}
(( $+functions[_walrus__help__share_commands] )) ||
_walrus__help__share_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help share commands' commands "$@"
}
(( $+functions[_walrus__help__stake_commands] )) ||
_walrus__help__stake_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help stake commands' commands "$@"
}
(( $+functions[_walrus__help__store_commands] )) ||
_walrus__help__store_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help store commands' commands "$@"
}
(( $+functions[_walrus__help__store-quilt_commands] )) ||
_walrus__help__store-quilt_commands() {
    local commands; commands=()
    _describe -t commands 'walrus help store-quilt commands' commands "$@"
}
(( $+functions[_walrus__info_commands] )) ||
_walrus__info_commands() {
    local commands; commands=(
'all:Print all information listed below' \
'epoch:Print epoch information' \
'storage:Print storage information' \
'size:Print size information' \
'price:Print price information' \
'bft:Print byzantine fault tolerance (BFT) information' \
'committee:Print committee information' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'walrus info commands' commands "$@"
}
(( $+functions[_walrus__info__all_commands] )) ||
_walrus__info__all_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info all commands' commands "$@"
}
(( $+functions[_walrus__info__bft_commands] )) ||
_walrus__info__bft_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info bft commands' commands "$@"
}
(( $+functions[_walrus__info__committee_commands] )) ||
_walrus__info__committee_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info committee commands' commands "$@"
}
(( $+functions[_walrus__info__epoch_commands] )) ||
_walrus__info__epoch_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info epoch commands' commands "$@"
}
(( $+functions[_walrus__info__help_commands] )) ||
_walrus__info__help_commands() {
    local commands; commands=(
'all:Print all information listed below' \
'epoch:Print epoch information' \
'storage:Print storage information' \
'size:Print size information' \
'price:Print price information' \
'bft:Print byzantine fault tolerance (BFT) information' \
'committee:Print committee information' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'walrus info help commands' commands "$@"
}
(( $+functions[_walrus__info__help__all_commands] )) ||
_walrus__info__help__all_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info help all commands' commands "$@"
}
(( $+functions[_walrus__info__help__bft_commands] )) ||
_walrus__info__help__bft_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info help bft commands' commands "$@"
}
(( $+functions[_walrus__info__help__committee_commands] )) ||
_walrus__info__help__committee_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info help committee commands' commands "$@"
}
(( $+functions[_walrus__info__help__epoch_commands] )) ||
_walrus__info__help__epoch_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info help epoch commands' commands "$@"
}
(( $+functions[_walrus__info__help__help_commands] )) ||
_walrus__info__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info help help commands' commands "$@"
}
(( $+functions[_walrus__info__help__price_commands] )) ||
_walrus__info__help__price_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info help price commands' commands "$@"
}
(( $+functions[_walrus__info__help__size_commands] )) ||
_walrus__info__help__size_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info help size commands' commands "$@"
}
(( $+functions[_walrus__info__help__storage_commands] )) ||
_walrus__info__help__storage_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info help storage commands' commands "$@"
}
(( $+functions[_walrus__info__price_commands] )) ||
_walrus__info__price_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info price commands' commands "$@"
}
(( $+functions[_walrus__info__size_commands] )) ||
_walrus__info__size_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info size commands' commands "$@"
}
(( $+functions[_walrus__info__storage_commands] )) ||
_walrus__info__storage_commands() {
    local commands; commands=()
    _describe -t commands 'walrus info storage commands' commands "$@"
}
(( $+functions[_walrus__json_commands] )) ||
_walrus__json_commands() {
    local commands; commands=()
    _describe -t commands 'walrus json commands' commands "$@"
}
(( $+functions[_walrus__list-blobs_commands] )) ||
_walrus__list-blobs_commands() {
    local commands; commands=()
    _describe -t commands 'walrus list-blobs commands' commands "$@"
}
(( $+functions[_walrus__list-patches-in-quilt_commands] )) ||
_walrus__list-patches-in-quilt_commands() {
    local commands; commands=()
    _describe -t commands 'walrus list-patches-in-quilt commands' commands "$@"
}
(( $+functions[_walrus__node-admin_commands] )) ||
_walrus__node-admin_commands() {
    local commands; commands=(
'collect-commission:Collect the commission' \
'vote-for-upgrade:Vote for a contract upgrade' \
'set-governance-authorized:Set the authorized entity for governance operations' \
'set-commission-authorized:Set the authorized entity for commission operations' \
'package-digest:Outputs the package digest of a sui package' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'walrus node-admin commands' commands "$@"
}
(( $+functions[_walrus__node-admin__collect-commission_commands] )) ||
_walrus__node-admin__collect-commission_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin collect-commission commands' commands "$@"
}
(( $+functions[_walrus__node-admin__help_commands] )) ||
_walrus__node-admin__help_commands() {
    local commands; commands=(
'collect-commission:Collect the commission' \
'vote-for-upgrade:Vote for a contract upgrade' \
'set-governance-authorized:Set the authorized entity for governance operations' \
'set-commission-authorized:Set the authorized entity for commission operations' \
'package-digest:Outputs the package digest of a sui package' \
'help:Print this message or the help of the given subcommand(s)' \
    )
    _describe -t commands 'walrus node-admin help commands' commands "$@"
}
(( $+functions[_walrus__node-admin__help__collect-commission_commands] )) ||
_walrus__node-admin__help__collect-commission_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin help collect-commission commands' commands "$@"
}
(( $+functions[_walrus__node-admin__help__help_commands] )) ||
_walrus__node-admin__help__help_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin help help commands' commands "$@"
}
(( $+functions[_walrus__node-admin__help__package-digest_commands] )) ||
_walrus__node-admin__help__package-digest_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin help package-digest commands' commands "$@"
}
(( $+functions[_walrus__node-admin__help__set-commission-authorized_commands] )) ||
_walrus__node-admin__help__set-commission-authorized_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin help set-commission-authorized commands' commands "$@"
}
(( $+functions[_walrus__node-admin__help__set-governance-authorized_commands] )) ||
_walrus__node-admin__help__set-governance-authorized_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin help set-governance-authorized commands' commands "$@"
}
(( $+functions[_walrus__node-admin__help__vote-for-upgrade_commands] )) ||
_walrus__node-admin__help__vote-for-upgrade_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin help vote-for-upgrade commands' commands "$@"
}
(( $+functions[_walrus__node-admin__package-digest_commands] )) ||
_walrus__node-admin__package-digest_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin package-digest commands' commands "$@"
}
(( $+functions[_walrus__node-admin__set-commission-authorized_commands] )) ||
_walrus__node-admin__set-commission-authorized_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin set-commission-authorized commands' commands "$@"
}
(( $+functions[_walrus__node-admin__set-governance-authorized_commands] )) ||
_walrus__node-admin__set-governance-authorized_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin set-governance-authorized commands' commands "$@"
}
(( $+functions[_walrus__node-admin__vote-for-upgrade_commands] )) ||
_walrus__node-admin__vote-for-upgrade_commands() {
    local commands; commands=()
    _describe -t commands 'walrus node-admin vote-for-upgrade commands' commands "$@"
}
(( $+functions[_walrus__publisher_commands] )) ||
_walrus__publisher_commands() {
    local commands; commands=()
    _describe -t commands 'walrus publisher commands' commands "$@"
}
(( $+functions[_walrus__pull-archive-blobs_commands] )) ||
_walrus__pull-archive-blobs_commands() {
    local commands; commands=()
    _describe -t commands 'walrus pull-archive-blobs commands' commands "$@"
}
(( $+functions[_walrus__read_commands] )) ||
_walrus__read_commands() {
    local commands; commands=()
    _describe -t commands 'walrus read commands' commands "$@"
}
(( $+functions[_walrus__read-quilt_commands] )) ||
_walrus__read-quilt_commands() {
    local commands; commands=()
    _describe -t commands 'walrus read-quilt commands' commands "$@"
}
(( $+functions[_walrus__remove-blob-attribute_commands] )) ||
_walrus__remove-blob-attribute_commands() {
    local commands; commands=()
    _describe -t commands 'walrus remove-blob-attribute commands' commands "$@"
}
(( $+functions[_walrus__remove-blob-attribute-fields_commands] )) ||
_walrus__remove-blob-attribute-fields_commands() {
    local commands; commands=()
    _describe -t commands 'walrus remove-blob-attribute-fields commands' commands "$@"
}
(( $+functions[_walrus__set-blob-attribute_commands] )) ||
_walrus__set-blob-attribute_commands() {
    local commands; commands=()
    _describe -t commands 'walrus set-blob-attribute commands' commands "$@"
}
(( $+functions[_walrus__share_commands] )) ||
_walrus__share_commands() {
    local commands; commands=()
    _describe -t commands 'walrus share commands' commands "$@"
}
(( $+functions[_walrus__stake_commands] )) ||
_walrus__stake_commands() {
    local commands; commands=()
    _describe -t commands 'walrus stake commands' commands "$@"
}
(( $+functions[_walrus__store_commands] )) ||
_walrus__store_commands() {
    local commands; commands=()
    _describe -t commands 'walrus store commands' commands "$@"
}
(( $+functions[_walrus__store-quilt_commands] )) ||
_walrus__store-quilt_commands() {
    local commands; commands=()
    _describe -t commands 'walrus store-quilt commands' commands "$@"
}

if [ "$funcstack[1]" = "_walrus" ]; then
    _walrus "$@"
else
    compdef _walrus walrus
fi

# 🔁 Search history with Ctrl+R
bindkey '^R' history-incremental-search-backward

# 🧠 Smart history with ↑ ↓
autoload -Uz up-line-or-beginning-search
autoload -Uz down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search   # arrow up
bindkey "^[[B" down-line-or-beginning-search # arrow down

# ⏩ Reload $PATH
zstyle ':completion:*' rehash true

# 📜 History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# Detect which `ls` flavor is in use
if ls --color > /dev/null 2>&1; then # GNU `ls`
	colorflag="--color"
	export LS_COLORS='no=00:fi=00:di=01;31:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:'
else # macOS `ls`
	colorflag="-G"
	export LSCOLORS='BxBxhxDxfxhxhxhxhxcxcx'
fi

# ↔️ Aliases
alias reload="source ~/.zshrc"
alias path='echo -e ${PATH//:/\\n}'
alias grep='grep --color=auto'
alias ls="command ls ${colorflag}"
alias ll="ls -lF ${colorflag}"
alias la="ls -lAF ${colorflag}"
alias dl="cd ~/Downloads"
alias dt="cd ~/Desktop"
alias tb="cd ~/Development/typeberry/"
alias g="git"
alias ga="git commit -a"

alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."

