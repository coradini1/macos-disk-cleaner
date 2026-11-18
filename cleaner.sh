#!/bin/bash
#
# cleaner.sh — interactive disk cleaner for macOS
# Shows what is eating your disk and lets YOU pick what to delete.
# Never touches critical system files. Always asks before deleting.
#
# Usage: bash cleaner.sh
# Keys:  ↑↓ move · space toggle · enter confirm · q back
#
# Tip: give your terminal "Full Disk Access" (System Settings →
# Privacy & Security), otherwise the Trash and some folders can't be read.
#

set -u
export LC_ALL=en_US.UTF-8

if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "Run it in a terminal:  bash cleaner.sh"; exit 1
fi

# ======================= STYLE =======================
# Note: variables are always written as ${VAR}; bash 3.2 (macOS default)
# would otherwise read a following "│" or "✻" as part of the variable name.
E=$'\033'
RST="${E}[0m"; BLD="${E}[1m"; DIM="${E}[2m"
ACC="${E}[38;5;173m"   # orange accent
GRY="${E}[38;5;245m"; GRN="${E}[38;5;114m"; YLW="${E}[38;5;179m"; RED="${E}[38;5;167m"; WHT="${E}[38;5;255m"
SPIN=('·' '✢' '✳' '✶' '✻' '✽' '✻' '✶' '✳' '✢')
VERBS=(Scanning Sniffing Digging Measuring Rummaging Weighing Combing)

AS="${HOME}/Library/Application Support"
CHROME="${AS}/Google/Chrome"
DEV="${HOME}/Library/Developer"
# apps like Chrome leave copies of themselves here when they update or stay open for days
XDIR=$(cd "$(dirname "$(getconf DARWIN_USER_DIR)")/X" 2>/dev/null && pwd -P)
BIG_MB=500   # "large files" threshold
MACOS=$(sw_vers -productVersion 2>/dev/null)
TMPD=$(mktemp -d)
F=""   # frame being built

# ======================= HELPERS =======================
disk() {   # "total free" in KB
  df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $2, $4}' || df -k / | awk 'NR==2 {print $2, $4}'
}
free_kb() { disk | awk '{print $2}'; }

# KB → "5.8 GB" (-2 = no permission / unknown)
hs() {
  [ "${1}" -lt 0 ] && { echo "?"; return; }
  awk -v k="${1}" 'BEGIN { if (k>=1048576) printf "%.1f GB", k/1048576; else if (k>=1024) printf "%d MB", k/1024; else printf "%d KB", k }'
}

rep() { local n=${2} s; [ "${n}" -lt 0 ] && n=0; printf -v s '%*s' "${n}" ''; printf '%s' "${s// /${1}}"; }
pad() { printf '%s%s' "${1}" "$(rep ' ' $(( ${2} - ${#1} )))"; }
lpad() { printf '%s%s' "$(rep ' ' $(( ${2} - ${#1} )))" "${1}"; }
trunc() { local s=${1}; [ ${#s} -gt "${2}" ] && s="${s:0:$(( ${2} - 1 ))}…"; printf '%s' "${s}"; }
trunc_left() { local s=${1}; [ ${#s} -gt "${2}" ] && s="…${s:$(( ${#s} - ${2} + 1 ))}"; printf '%s' "${s}"; }
vis() { local s; s=$(printf '%s' "${1}" | sed "s/${E}\[[0-9;?]*[a-zA-Z]//g"); echo ${#s}; }
verb() { echo "${VERBS[RANDOM % ${#VERBS[@]}]}"; }
chrome_open() { pgrep -x "Google Chrome" >/dev/null; }
tilde() { case ${1} in "${HOME}"/*) printf '~%s' "${1#${HOME}}" ;; *) printf '%s' "${1}" ;; esac; }
kb_of() { du -sk "${1}" 2>/dev/null | awk '{print $1}'; }

ago() {
  local d=${1}
  if   [ "${d}" -lt 1 ];   then echo "today"
  elif [ "${d}" -lt 2 ];   then echo "yesterday"
  elif [ "${d}" -lt 30 ];  then echo "${d} days ago"
  elif [ "${d}" -lt 60 ];  then echo "1 month ago"
  elif [ "${d}" -lt 365 ]; then echo "$((d/30)) months ago"
  elif [ "${d}" -lt 730 ]; then echo "1 year ago"
  else echo "$((d/365)) years ago"; fi
}

# bar KB MAX WIDTH COLOR
bar() {
  local kb=${1} max=${2} w=${3} col=${4}
  if [ "${w}" -le 0 ]; then return; fi
  if [ "${kb}" -le 0 ] || [ "${max}" -le 0 ]; then printf '%s' "${GRY}$(rep '─' "${w}")${RST}"; return; fi
  local eighths=$(( kb * w * 8 / max )) part=('' '▏' '▎' '▍' '▌' '▋' '▊' '▉')
  [ ${eighths} -gt $((w*8)) ] && eighths=$((w*8)); [ ${eighths} -lt 1 ] && eighths=1
  local full=$((eighths/8)) rest=$((eighths%8)) used
  used=${full}; [ ${rest} -gt 0 ] && used=$((used+1))
  printf '%s' "${col}$(rep '█' ${full})${part[${rest}]}${GRY}$(rep '─' $((w-used)))${RST}"
}

# moves a path to the Trash through Finder (works without Full Disk Access)
to_trash() {
  osascript -e 'on run argv' -e 'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)' -e 'end run' "${1}" >/dev/null 2>&1
  [ -e "${1}" ] && mv "${1}" "${HOME}/.Trash/" 2>/dev/null
  [ ! -e "${1}" ]
}

empty_trash() {
  empty_dir "${HOME}/.Trash" && return 0
  osascript -e 'tell application "Finder" to empty trash' >/dev/null 2>&1
}

# ======================= SCREEN =======================
measure() {
  local s; s=$(stty size </dev/tty 2>/dev/null)
  LINES_=${s% *}; COLS_=${s#* }
  [ -z "${LINES_}" ] && LINES_=24; [ -z "${COLS_}" ] && COLS_=80
  W=${COLS_}; [ ${W} -gt 80 ] && W=80; [ ${W} -lt 50 ] && W=50
  L=30; [ ${W} -lt 72 ] && L=$((W-42))
}

fl() { F+="${1}${E}[K"$'\n'; }            # append a line to the frame
show() { printf '%s' "${F}${E}[J"; F=""; }

boxline() {   # line inside a box: left text, optional right text
  local left=${1} right=${2:-} bc=${BC:-${GRY}}
  fl "${bc}│${RST} ${left}$(rep ' ' $(( W - 4 - $(vis "${left}") - $(vis "${right}") )))${right} ${bc}│${RST}"
}

header() {
  measure
  local tot fre; read -r tot fre <<< "$(disk)"
  local pct=$(( (tot-fre) * 100 / tot )) col=${GRN}
  [ ${pct} -ge 75 ] && col=${YLW}; [ ${pct} -ge 90 ] && col=${RED}
  F="${E}[H"
  fl "${GRY}╭$(rep '─' $((W-2)))╮${RST}"
  boxline "${ACC}✻${RST} ${BLD}${WHT}macOS Disk Cleaner${RST}" "${GRY}macOS ${MACOS}${RST}"
  boxline ""
  boxline "$(bar $((tot-fre)) "${tot}" $((W-16)) "${col}") ${BLD}$(lpad "${pct}%" 4)${RST} ${GRY}used${RST}"
  boxline "${BLD}$(hs "${fre}")${RST} ${GRY}free of $(hs "${tot}")${RST}"
  fl "${GRY}╰$(rep '─' $((W-2)))╯${RST}"
}

footer() { fl "  ${GRY}$(rep '─' $((W-4)))${RST}"; fl "  ${GRY}${1}${RST}"; }

# ---------- live header: the disk bar animates while things get deleted ----------
# The header (rows 1-7) is pinned with a scroll region; results scroll below it.
LIVE_START=""

live_begin() {   # live_begin START_FREE_KB
  LIVE_START=${1}; LIVE_SHOWN=${1}; LIVE_TARGET=${1}; LIVE_T=0
  read -r LIVE_TOT _ <<< "$(disk)"
  printf '%s' "${E}[8;${LINES_}r${E}[8;1H"
}

live_end() { LIVE_START=""; printf '%s' "${E}7${E}[r${E}8"; }

# bar with the space reclaimed so far highlighted in green
bar_live() {   # bar_live USED GAINED TOTAL WIDTH COLOR
  local used=${1} gained=${2} tot=${3} w=${4} col=${5}
  local eighths=$(( used * w * 8 / tot )) part=('' '▏' '▎' '▍' '▌' '▋' '▊' '▉')
  local full=$((eighths/8)) rest=$((eighths%8)) cells g
  cells=${full}; [ ${rest} -gt 0 ] && cells=$((cells+1))
  g=$(( (gained * w + tot - 1) / tot )); [ ${gained} -le 0 ] && g=0
  [ $((cells+g)) -gt ${w} ] && g=$((w-cells))
  printf '%s' "${col}$(rep '█' ${full})${part[${rest}]}${GRN}$(rep '░' ${g})${GRY}$(rep '─' $((w-cells-g)))${RST}"
}

live_draw() {
  local used=$((LIVE_TOT-LIVE_SHOWN)) gained=$((LIVE_SHOWN-LIVE_START)) pct col=${GRN} saved=${F} right=""
  [ ${gained} -lt 0 ] && gained=0
  pct=$(( used * 100 / LIVE_TOT ))
  [ ${pct} -ge 75 ] && col=${YLW}; [ ${pct} -ge 90 ] && col=${RED}
  [ ${gained} -ge 1024 ] && right="${GRN}▲ $(hs ${gained}) freed${RST}"
  F=""
  boxline "$(bar_live ${used} ${gained} ${LIVE_TOT} $((W-16)) "${col}") ${BLD}$(lpad "${pct}%" 4)${RST} ${GRY}used${RST}"
  boxline "${BLD}$(hs ${LIVE_SHOWN})${RST} ${GRY}free of $(hs ${LIVE_TOT})${RST}" "${right}"
  printf '%s' "${E}7${E}[4;1H${F}${E}8"
  F=${saved}
}

# one animation frame: poll the disk now and then, ease the numbers towards it
live_tick() {
  [ -n "${LIVE_START}" ] || return 0
  LIVE_T=$((LIVE_T+1))
  [ $((LIVE_T % 5)) = 1 ] && LIVE_TARGET=$(free_kb)
  local diff=$((LIVE_TARGET-LIVE_SHOWN)) step
  [ ${diff} = 0 ] && return 0
  step=$((diff/4)); [ ${step} = 0 ] && step=${diff}
  LIVE_SHOWN=$((LIVE_SHOWN+step))
  live_draw
}

# keep animating for a moment after the last deletion so the bar settles
live_settle() {
  local i
  for ((i=0; i<30; i++)); do
    live_tick; sleep 0.08
    [ ${i} -gt 12 ] && [ "${LIVE_TARGET}" = "${LIVE_SHOWN}" ] && break
  done
}

key() {
  local k r
  IFS= read -rsn1 k
  if [ "${k}" = "${E}" ]; then IFS= read -rsn2 -t 1 r; k="${k}${r}"; fi
  case "${k}" in
    "${E}[A"|k|K) echo up ;;
    "${E}[B"|j|J) echo down ;;
    " ")          echo space ;;
    "")           echo enter ;;
    q|Q|"${E}")   echo quit ;;
    a|A)          echo all ;;
    n|N)          echo none ;;
    y|Y)          echo yes ;;
    r|R)          echo refresh ;;
    o|O)          echo old ;;
    t|T)          echo trash ;;
    d|D)          echo delete ;;
    [1-9])        echo "${k}" ;;
    *)            echo other ;;
  esac
}

wait_enter() {
  fl ""; fl "  ${GRY}↵ enter to go back${RST}"; show
  local k; while :; do k=$(key); case ${k} in enter|quit) return ;; esac; done
}

# runs "$@" in the background with a spinner; returns the command's exit code
work() {
  local msg=${1}; shift
  "$@" & local pid=$! i=0 t0=${SECONDS}
  while kill -0 ${pid} 2>/dev/null; do
    printf '\r  %s%s%s %s%s…%s %s(%ds)%s%s' "${ACC}" "${SPIN[i%10]}" "${RST}" "${WHT}" "$(trunc "${msg}" $((W-16)))" "${RST}" "${GRY}" $((SECONDS-t0)) "${RST}" "${E}[K"
    live_tick
    i=$((i+1)); sleep 0.08
  done
  printf '\r%s' "${E}[K"
  wait ${pid}
}

result() {   # ⏺ title / ⎿ outcome
  printf '  %s⏺%s %s%s%s\n     %s⎿%s  %s\n' "${1}" "${RST}" "${BLD}${WHT}" "$(trunc "${2}" $((W-6)))" "${RST}" "${GRY}" "${RST}" "${3}"
}

summary() {   # summary START_KB ESTIMATED_KB
  local now real; now=$(free_kb); real=$(( now - ${1} )); [ ${real} -lt 0 ] && real=0
  BC=${GRN}
  fl ""
  fl "${GRN}╭$(rep '─' $((W-2)))╮${RST}"
  boxline "${GRN}✓${RST} ${BLD}${WHT}Done!${RST}  ${BLD}$(hs ${real})${RST} freed"
  boxline "${GRY}before $(hs "${1}") free  →  now ${RST}${BLD}$(hs "${now}")${RST}${GRY} free${RST}"
  if [ "${2}" -gt $(( real + 1048576 )) ]; then
    boxline "${GRY}items add up to ~$(hs "${2}"); macOS may take a few minutes to show it${RST}"
  fi
  fl "${GRN}╰$(rep '─' $((W-2)))╯${RST}"
  BC=""
}

# ======================= CLEANABLE ITEMS =======================
ITEMS=(app_clones chrome_sw caches logs dotcache npm pnpm bun cargo go conda gradle media mail vscode apps
       xcode device_support sims android ios_updates brew docker stremio xcode_archives ios_backups trash)

info() {   # sets NAME DESC SAFE NEEDS_CHROME_CLOSED
  SAFE=1; NEEDS_CHROME_CLOSED=0
  case ${1} in
    app_clones)     NAME="App leftover copies";         DESC="copies apps like Chrome leave behind · the ones in use are kept" ;;
    chrome_sw)      NAME="Chrome Service Worker";       DESC="offline website cache · you stay logged in"; NEEDS_CHROME_CLOSED=1 ;;
    caches)         NAME="App caches";                  DESC="~/Library/Caches · apps rebuild it on their own" ;;
    logs)           NAME="Logs";                        DESC="old app logs" ;;
    dotcache)       NAME="~/.cache";                    DESC="dev tool caches (puppeteer, huggingface…)" ;;
    npm)            NAME="npm cache";                   DESC="downloaded again when needed" ;;
    pnpm)           NAME="pnpm store";                  DESC="only removes packages no project uses" ;;
    bun)            NAME="Bun cache";                   DESC="downloaded again when needed" ;;
    cargo)          NAME="Rust/Cargo cache";            DESC="crate downloads · fetched again on next build" ;;
    go)             NAME="Go module cache";             DESC="go clean -modcache · fetched again on next build" ;;
    conda)          NAME="Conda packages";              DESC="conda clean --all · unused package tarballs and caches" ;;
    gradle)         NAME="Gradle cache";                DESC="Android/Java · downloaded again on next build" ;;
    media)          NAME="macOS photo analysis cache";  DESC="macOS rebuilds it over time" ;;
    mail)           NAME="Mail attachments cache";      DESC="attachments you opened in Mail · they stay in the emails" ;;
    vscode)         NAME="VS Code cache";               DESC="rebuilt when VS Code opens" ;;
    apps)           NAME="Discord/Spotify cache";       DESC="cached media and songs" ;;
    xcode)          NAME="Xcode DerivedData";           DESC="temporary Xcode builds" ;;
    device_support) NAME="Xcode device support";        DESC="debug symbols for devices · recreated when you plug one in" ;;
    sims)           NAME="Broken iOS simulators";       DESC="simulators from Xcode versions you no longer have" ;;
    android)        NAME="Android emulator images";     DESC="re-download from Android Studio when needed"; SAFE=0 ;;
    ios_updates)    NAME="iPhone/iPad update files";    DESC="old iOS installers downloaded by Finder" ;;
    brew)           NAME="Homebrew";                    DESC="old package versions and downloads" ;;
    docker)         NAME="Docker";                      DESC="docker system prune -a · unused images, containers, build cache"; SAFE=0 ;;
    stremio)        NAME="Stremio";                     DESC="cached movies" ;;
    xcode_archives) NAME="Xcode Archives";              DESC="old app builds · keep the ones you still ship"; SAFE=0 ;;
    ios_backups)    NAME="iPhone/iPad backups";         DESC="local device backups · make sure you have another one"; SAFE=0 ;;
    trash)          NAME="Trash";                       DESC="PERMANENT · these are your files"; SAFE=0 ;;
  esac
}

paths() {
  local d
  case ${1} in
    app_clones)     [ -n "${XDIR}" ] && for d in "${XDIR}"/*code_sign_clone; do [ -d "${d}" ] && echo "${d}"; done ;;
    chrome_sw)      for d in "${CHROME}"/Default "${CHROME}"/Profile\ *; do echo "${d}/Service Worker"; done ;;
    caches)         echo "${HOME}/Library/Caches" ;;
    logs)           echo "${HOME}/Library/Logs" ;;
    dotcache)       echo "${HOME}/.cache" ;;
    npm)            echo "${HOME}/.npm" ;;
    pnpm)           d=$(pnpm store path 2>/dev/null); echo "${d:-${HOME}/Library/pnpm}" ;;
    bun)            echo "${HOME}/.bun/install/cache" ;;
    cargo)          printf '%s\n' "${HOME}/.cargo/registry/cache" "${HOME}/.cargo/registry/src" "${HOME}/.cargo/git/checkouts" ;;
    go)             go env GOMODCACHE 2>/dev/null ;;
    conda)          d=$(conda info --base 2>/dev/null) && echo "${d}/pkgs" ;;
    gradle)         printf '%s\n' "${HOME}/.gradle/caches" "${HOME}/.gradle/daemon" "${HOME}/.gradle/wrapper/dists" ;;
    media)          echo "${HOME}/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/com.apple.mediaanalysisd" ;;
    mail)           echo "${HOME}/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" ;;
    vscode)         printf '%s\n' "${AS}/Code/Cache" "${AS}/Code/CachedData" "${AS}/Code/Code Cache" ;;
    apps)           printf '%s\n' "${AS}/discord/Cache" "${AS}/Spotify/PersistentCache" ;;
    xcode)          echo "${DEV}/Xcode/DerivedData" ;;
    device_support) for d in iOS watchOS tvOS visionOS; do echo "${DEV}/Xcode/${d} DeviceSupport"; done ;;
    sims)
      # only ask xcrun if simulators exist, otherwise it may pop up the developer tools installer
      [ -d "${DEV}/CoreSimulator/Devices" ] || return
      xcrun simctl list devices unavailable 2>/dev/null | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' |
        while read -r d; do echo "${DEV}/CoreSimulator/Devices/${d}"; done ;;
    android)        echo "${HOME}/Library/Android/sdk/system-images" ;;
    ios_updates)    printf '%s\n' "${HOME}/Library/iTunes/iPhone Software Updates" "${HOME}/Library/iTunes/iPad Software Updates" ;;
    stremio)        echo "${AS}/stremio-server" ;;
    xcode_archives) echo "${DEV}/Xcode/Archives" ;;
    ios_backups)    echo "${AS}/MobileSync/Backup" ;;
    trash)          echo "${HOME}/.Trash" ;;
  esac
}

# size in KB (-1 = doesn't exist, -2 = no permission to read)
size_of() {
  local id=${1} kb=0 found=0 err=0 p s
  case ${id} in
    npm|pnpm|go|conda) command -v "${id}" >/dev/null || { echo -1; return; } ;;
    brew)
      command -v brew >/dev/null || { echo -1; return; }
      brew cleanup -n -s --prune=all 2>/dev/null | awk '
        match($0, /approximately [0-9.]+[KMG]?B/) {
          s = substr($0, RSTART+14, RLENGTH-14); n = s + 0
          if (s ~ /GB/) n *= 1048576; else if (s ~ /MB/) n *= 1024; else if (s !~ /KB/) n /= 1024
          printf "%d\n", n; f = 1 }
        END { if (!f) print 0 }'
      return ;;
    docker)
      command -v docker >/dev/null && docker info >/dev/null 2>&1 || { echo -1; return; }
      docker system df --format '{{.Reclaimable}}' 2>/dev/null | awk '
        { v = $1 + 0; u = $1; gsub(/[0-9.]/, "", u)
          if (u == "TB") v *= 1073741824; else if (u == "GB") v *= 1048576; else if (u == "MB") v *= 1024; else if (u == "B") v /= 1024
          t += v }
        END { printf "%d\n", t }'
      return ;;
  esac
  while IFS= read -r p; do
    [ -n "${p}" ] && [ -e "${p}" ] || continue
    found=1
    s=$(kb_of "${p}")
    if [ -z "${s}" ]; then err=1; else kb=$((kb+s)); fi
  done < <(paths "${id}")
  if [ ${found} = 0 ]; then echo -1
  elif [ ${err} = 1 ] && [ ${kb} = 0 ]; then echo -2
  else echo ${kb}; fi
}

# empties a folder; fails if something is left or it couldn't be read
empty_dir() {
  find "${1}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  local left; left=$(ls -A "${1}" 2>/dev/null) || return 1
  [ -z "${left}" ]
}

# deletes leftover app copies, keeping the ones a running app still uses
clean_clones() {
  local root d out rc=0
  while IFS= read -r root; do
    out=$(lsof +D "${root}" 2>/dev/null)
    for d in "${root}"/*; do
      [ -e "${d}" ] || continue
      printf '%s\n' "${out}" | grep -qF "${d}/" && continue
      rm -rf "${d}" 2>/dev/null; [ -e "${d}" ] && rc=1
    done
  done < <(paths app_clones)
  return ${rc}
}

clean_item() {
  local p rc=0
  case ${1} in
    app_clones) clean_clones || rc=1 ;;
    npm)    npm cache clean --force >/dev/null 2>&1 || rc=1 ;;
    pnpm)   pnpm store prune >/dev/null 2>&1 || rc=1 ;;
    go)     go clean -modcache >/dev/null 2>&1 || rc=1 ;;
    conda)  conda clean --all --yes >/dev/null 2>&1 || rc=1 ;;
    brew)   brew cleanup -s --prune=all >/dev/null 2>&1 || rc=1 ;;
    docker) docker system prune -a -f >/dev/null 2>&1 || rc=1 ;;
    sims)   xcrun simctl delete unavailable >/dev/null 2>&1 || rc=1 ;;
    trash)  empty_trash || rc=1 ;;
    chrome_sw|gradle)
      while IFS= read -r p; do
        [ -e "${p}" ] || continue
        rm -rf "${p}" 2>/dev/null; [ -e "${p}" ] && rc=1
      done < <(paths "${1}") ;;
    *)
      while IFS= read -r p; do
        [ -n "${p}" ] && [ -d "${p}" ] || continue
        empty_dir "${p}" || rc=1
      done < <(paths "${1}") ;;
  esac
  return ${rc}
}

compute_sizes() {
  local id
  for id in "${ITEMS[@]}"; do echo "${id} $(size_of "${id}")"; done > "${TMPD}/sizes"
}

compute_all() {
  local id kb a p
  : > "${TMPD}/sizes"; : > "${TMPD}/scan"
  for id in "${ITEMS[@]}"; do
    kb=$(size_of "${id}"); info "${id}"
    echo "${id} ${kb}" >> "${TMPD}/sizes"; echo "${kb}|${NAME}|C" >> "${TMPD}/scan"
  done
  for a in "Downloads|${HOME}/Downloads" "Desktop|${HOME}/Desktop" "Documents|${HOME}/Documents" \
           "Pictures|${HOME}/Pictures" "Movies|${HOME}/Movies" "Music|${HOME}/Music" \
           "WhatsApp media|${HOME}/Library/Group Containers/group.net.whatsapp.WhatsApp.shared" \
           "Downloaded macOS update|/Library/Updates"; do
    p=${a#*|}; [ -e "${p}" ] || continue
    kb=$(kb_of "${p}")
    echo "${kb:--2}|${a%%|*}|M" >> "${TMPD}/scan"
  done
}

# ======================= CHECKLIST =======================
# Uses: CL_ID CL_LBL CL_KB CL_HS CL_SEL CL_DIS CL_NOTE CL_EXTRA CL_DAYS, CL_TITLE CL_SUB CL_KEYS CL_HOOK
reset_cl() { CL_ID=(); CL_LBL=(); CL_KB=(); CL_HS=(); CL_SEL=(); CL_DIS=(); CL_NOTE=(); CL_EXTRA=(); CL_DAYS=(); }

item_row() {
  local i=${1} cur=${2} max=${3} ptr="  " mk="${GRY}○${RST}" lb end
  [ "${CL_SEL[i]}" = 1 ] && mk="${ACC}◉${RST}"
  lb=$(pad "$(trunc "${CL_LBL[i]}" ${L})" ${L})
  if [ -n "${CL_DIS[i]}" ]; then
    mk="${DIM}${GRY}○${RST}"; lb="${DIM}${GRY}${lb}${RST}"; end="${YLW}${CL_DIS[i]}${RST}"
  else
    if [ -n "${CL_EXTRA[i]:-}" ]; then end=${CL_EXTRA[i]}
    elif [ "${CL_SEL[i]}" = 1 ]; then end=$(bar "${CL_KB[i]}" "${max}" $((W-L-20)) "${ACC}")
    else end=$(bar "${CL_KB[i]}" "${max}" $((W-L-20)) "${GRY}"); fi
    [ "${i}" = "${cur}" ] && lb="${BLD}${WHT}${lb}${RST}"
  fi
  [ "${i}" = "${cur}" ] && ptr="${ACC}❯${RST} "
  fl "  ${ptr}${mk} ${lb} $(lpad "${CL_HS[i]}" 9)  ${end}"
}

checklist() {
  local n=${#CL_LBL[@]} cur=0 off=0 k i rows max cnt tot note
  while true; do
    header
    rows=$((LINES_-18)); [ ${rows} -lt 3 ] && rows=3
    [ ${cur} -lt ${off} ] && off=${cur}
    [ ${cur} -ge $((off+rows)) ] && off=$((cur-rows+1))
    max=1; cnt=0; tot=0
    for ((i=0; i<n; i++)); do
      [ "${CL_KB[i]}" -gt ${max} ] && max=${CL_KB[i]}
      if [ "${CL_SEL[i]}" = 1 ]; then cnt=$((cnt+1)); [ "${CL_KB[i]}" -gt 0 ] && tot=$((tot+CL_KB[i])); fi
    done

    fl ""
    fl "  ${BLD}${WHT}${CL_TITLE}${RST}"
    fl "  ${GRY}$(trunc "${CL_SUB}" $((W-4)))${RST}"
    if [ ${off} -gt 0 ]; then fl "    ${GRY}↑ ${off} more${RST}"; else fl ""; fi
    for ((i=off; i<n && i<off+rows; i++)); do item_row ${i} ${cur} ${max}; done
    if [ $((n-off-rows)) -gt 0 ]; then fl "    ${GRY}↓ $((n-off-rows)) more${RST}"; else fl ""; fi
    note=${CL_NOTE[cur]}
    [ "${CL_DIS[cur]}" = "Chrome is open" ] && note="quit Chrome with Cmd+Q, then press r"
    fl "  ${GRY}⎿  $(trunc_left "${note}" $((W-7)))${RST}"
    fl ""
    fl "  Selected: ${BLD}${cnt}${RST} · ${BLD}${ACC}~$(hs ${tot})${RST}"
    footer "↑↓ · space toggle · a all · n none${CL_KEYS} · enter delete · q back"
    show

    k=$(key)
    case ${k} in
      up)    cur=$(( (cur-1+n) % n )) ;;
      down)  cur=$(( (cur+1) % n )) ;;
      space) [ -z "${CL_DIS[cur]}" ] && CL_SEL[cur]=$(( 1 - CL_SEL[cur] )) ;;
      all)   for ((i=0; i<n; i++)); do [ -z "${CL_DIS[i]}" ] && CL_SEL[i]=1; done ;;
      none)  for ((i=0; i<n; i++)); do CL_SEL[i]=0; done ;;
      enter) [ ${cnt} -gt 0 ] && return 0 ;;
      quit)  return 1 ;;
      *)     [ -n "${CL_HOOK:-}" ] && "${CL_HOOK}" "${k}" ;;
    esac
  done
}

# confirm_screen [files]  — with "files" it asks Trash vs permanent delete and sets MODE
confirm_screen() {
  local n=${#CL_LBL[@]} i cnt=0 tot=0 trash=0 lim=$((LINES_-17)) k
  header
  fl ""; fl "  ${BLD}${WHT}About to delete${RST}"; fl ""
  for ((i=0; i<n; i++)); do
    [ "${CL_SEL[i]}" = 1 ] || continue
    cnt=$((cnt+1)); [ "${CL_KB[i]}" -gt 0 ] && tot=$((tot+CL_KB[i]))
    [ "${CL_ID[i]}" = trash ] && trash=1
    [ ${cnt} -le ${lim} ] && fl "  ${ACC}•${RST} $(pad "$(trunc "${CL_LBL[i]}" ${L})" ${L}) ${GRY}$(lpad "${CL_HS[i]}" 9)${RST}"
  done
  [ ${cnt} -gt ${lim} ] && fl "  ${GRY}… and $((cnt-lim)) more${RST}"
  fl ""
  [ ${trash} = 1 ] && fl "  ${RED}⚠ Emptying the Trash can't be undone: those files are gone for good.${RST}"
  if [ "${1:-}" = files ]; then
    fl "  Total ${BLD}~$(hs ${tot})${RST}"
    fl "  ${BLD}t${RST} move to Trash ${GRY}(can undo)${RST} · ${BLD}d${RST} delete permanently · ${GRY}other key cancels${RST}"
    show
    k=$(key)
    case ${k} in trash) MODE=trash ;; delete) MODE=delete ;; *) return 1 ;; esac
    return 0
  fi
  fl "  Total ${BLD}~$(hs ${tot})${RST} · ${BLD}Confirm?${RST}  ${GRY}y = yes · any other key cancels${RST}"
  show
  [ "$(key)" = yes ]
}

hook_old() {
  [ "${1}" = old ] || return 0
  local i
  for ((i=0; i<${#CL_ID[@]}; i++)); do
    [ -z "${CL_DIS[i]}" ] && [ "${CL_DAYS[i]}" -ge "${OLD_DAYS}" ] && CL_SEL[i]=1
  done
}

# ======================= SCREENS =======================
scan() {
  header; fl ""; show
  work "$(verb) your disk" compute_all
  local -a kb name kind
  local a b c n i max=1 sum=0 lim bw tag col
  while IFS='|' read -r a b c; do kb+=("${a}"); name+=("${b}"); kind+=("${c}"); done \
    < <(awk -F'|' '$1>=1024 || $1==-2' "${TMPD}/scan" | sort -t'|' -k1,1nr)
  n=${#kb[@]}
  for ((i=0; i<n; i++)); do
    [ "${kb[i]}" -gt ${max} ] && max=${kb[i]}
    [ "${kind[i]}" = C ] && [ "${kb[i]}" -gt 0 ] && sum=$((sum+kb[i]))
  done

  header
  lim=$((LINES_-17)); bw=$((W-L-30))
  fl ""; fl "  ${BLD}${WHT}What's using your disk${RST}"; fl ""
  for ((i=0; i<n && i<lim; i++)); do
    if [ "${kind[i]}" = C ]; then tag="${GRN}● cleanable${RST}"; col=${ACC}; else tag="${GRY}○ your call${RST}"; col=${GRY}; fi
    fl "  $(pad "$(trunc "${name[i]}" ${L})" ${L}) ${BLD}$(lpad "$(hs "${kb[i]}")" 9)${RST}  $(bar "${kb[i]}" ${max} ${bw} "${col}") ${tag}"
  done
  [ ${n} -gt ${lim} ] && fl "  ${GRY}… and $((n-lim)) more${RST}"
  fl ""
  fl "  ${ACC}✻${RST} You can free ${BLD}~$(hs ${sum})${RST} with ${BLD}Clean${RST} · big folders? try ${BLD}Large files${RST}"
  fl "  ${GRY}? = no permission to read · APFS may report sizes larger than the real usage${RST}"
  grep -q '|Downloaded macOS update|' "${TMPD}/scan" && fl "  ${GRY}macOS update: install it in System Settings → General → Software Update${RST}"
  wait_enter
}

hook_chrome() {
  [ "${1}" = refresh ] || return 0
  chrome_open && return 0
  local i
  for ((i=0; i<${#CL_ID[@]}; i++)); do
    if [ "${CL_DIS[i]}" = "Chrome is open" ]; then CL_DIS[i]=""; CL_SEL[i]=1; fi
  done
  CL_KEYS=""
}

clean() {
  [ -s "${TMPD}/sizes" ] || { header; fl ""; show; work "$(verb) your disk" compute_sizes; }
  reset_cl
  local id kb open=0 note
  chrome_open && open=1
  while read -r id kb; do
    [ "${kb}" = -1 ] && continue
    [ "${kb}" -ge 0 ] && [ "${kb}" -lt 1024 ] && continue
    info "${id}"
    note=${DESC}; [ "${kb}" = -2 ] && note="${DESC} · size unknown without Full Disk Access"
    CL_ID+=("${id}"); CL_LBL+=("${NAME}"); CL_KB+=("${kb}"); CL_HS+=("$(hs "${kb}")"); CL_NOTE+=("${note}"); CL_EXTRA+=("")
    if [ ${NEEDS_CHROME_CLOSED} = 1 ] && [ ${open} = 1 ]; then CL_DIS+=("Chrome is open"); CL_SEL+=(0)
    else CL_DIS+=(""); CL_SEL+=("${SAFE}"); fi
  done < "${TMPD}/sizes"

  if [ ${#CL_ID[@]} = 0 ]; then
    header; fl ""; fl "  ${GRN}⏺${RST} Nothing to clean, you're all set."; wait_enter; return
  fi
  CL_TITLE="What to delete"
  CL_SUB="checked items are safe, the system rebuilds them · the rest is your call"
  CL_KEYS=""; [ ${open} = 1 ] && CL_KEYS=" · r refresh"
  CL_HOOK=hook_chrome
  checklist || return
  confirm_screen || return

  local n=${#CL_ID[@]} i before after freed rc sum=0 start
  start=$(free_kb)
  header; fl ""; show
  live_begin "${start}"
  for ((i=0; i<n; i++)); do
    [ "${CL_SEL[i]}" = 1 ] || continue
    id=${CL_ID[i]}; info "${id}"; before=${CL_KB[i]}
    if [ ${NEEDS_CHROME_CLOSED} = 1 ] && chrome_open; then
      result "${YLW}" "${NAME}" "skipped · Chrome was opened again"; continue
    fi
    work "Cleaning ${NAME}" clean_item "${id}"; rc=$?
    after=$(size_of "${id}"); [ "${after}" = -1 ] && after=0
    freed=-1
    if [ "${before}" -ge 0 ] && [ "${after}" -ge 0 ]; then
      freed=$((before-after)); [ ${freed} -lt 0 ] && freed=0; sum=$((sum+freed))
    fi
    if [ ${rc} = 0 ]; then
      if [ ${freed} -ge 0 ]; then result "${GRN}" "${NAME}" "$(hs ${freed}) freed"; else result "${GRN}" "${NAME}" "cleaned"; fi
    elif [ ${freed} -gt 0 ]; then result "${YLW}" "${NAME}" "$(hs ${freed}) freed · some files were in use"
    else result "${RED}" "${NAME}" "failed · no permission (give your terminal Full Disk Access)"
    fi
  done
  rm -f "${TMPD}/sizes"   # sizes changed, measure again next time
  live_settle
  summary "${start}" ${sum}
  wait_enter
  live_end
}

# ---------- file pickers: large files, installers, unused apps ----------
# each finder writes "KB|DAYS|PATH" lines to ${TMPD}/files

find_large() {
  local now f kb min=$((BIG_MB*1024))
  now=$(date +%s)
  find "${HOME}" /Users/Shared -xdev \
       \( -path "${HOME}/Library" -o -path "${HOME}/.Trash" -o -name node_modules -o -name .git \
          -o -name "*.app" -o -name "*.photoslibrary" -o -name "*.musiclibrary" -o -name "*.tvlibrary" \
          -o -name "*.photolibrary" -o -name "*.fcpbundle" \) -prune \
       -o -type f -size +${BIG_MB}M -print 2>/dev/null |
  while IFS= read -r f; do
    kb=$(kb_of "${f}")
    # skip iCloud placeholders: big on paper, nothing on disk
    [ -n "${kb}" ] && [ "${kb}" -ge "${min}" ] || continue
    echo "${kb}|$(( (now - $(stat -f %m "${f}")) / 86400 ))|${f}"
  done | sort -t'|' -k1,1nr | head -300 > "${TMPD}/files"
}

find_installers() {
  local now f kb
  now=$(date +%s)
  find "${HOME}/Downloads" "${HOME}/Desktop" "${HOME}/Documents" -maxdepth 4 -type f \
       \( -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.mpkg' -o -iname '*.iso' -o -iname '*.xip' \
          -o -iname '*.zip' -o -iname '*.rar' -o -iname '*.7z' \) -print 2>/dev/null |
  while IFS= read -r f; do
    kb=$(kb_of "${f}"); [ -n "${kb}" ] || continue
    case ${f} in
      *.[zZ][iI][pP]|*.[rR][aA][rR]|*.7[zZ]) [ "${kb}" -ge 51200 ] || continue ;;   # only archives ≥ 50 MB
      *) [ "${kb}" -ge 1024 ] || continue ;;
    esac
    echo "${kb}|$(( (now - $(stat -f %m "${f}")) / 86400 ))|${f}"
  done | sort -t'|' -k1,1nr > "${TMPD}/files"
}

find_apps() {
  local now app id used t kb
  now=$(date +%s)
  for app in /Applications/*.app "${HOME}/Applications"/*.app; do
    [ -d "${app}" ] || continue
    id=$(mdls -raw -name kMDItemCFBundleIdentifier "${app}" 2>/dev/null)
    case ${id} in com.apple.*) continue ;; esac   # never offer Apple's own apps
    used=$(mdls -raw -name kMDItemLastUsedDate "${app}" 2>/dev/null)
    [ "${used}" = "(null)" ] && used=$(mdls -raw -name kMDItemDateAdded "${app}" 2>/dev/null)
    t=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "${used}" +%s 2>/dev/null) || continue
    kb=$(kb_of "${app}"); [ -n "${kb}" ] || continue
    echo "${kb}|$(( (now - t) / 86400 ))|${app}"
  done | sort -t'|' -k2,2nr > "${TMPD}/files"
}

# pick_files FINDER "search message" "title" "subtitle" "verb for dates" OLD_DAYS
pick_files() {
  local finder=${1} msg=${2} title=${3} sub=${4} verb_=${5}
  OLD_DAYS=${6}
  header; fl ""; show
  work "${msg}" "${finder}"
  reset_cl
  local kb days p name col
  while IFS='|' read -r kb days p; do
    name=${p##*/}
    col=${GRY}; [ "${days}" -ge "${OLD_DAYS}" ] && col=${YLW}
    CL_ID+=("${p}"); CL_LBL+=("${name}"); CL_KB+=("${kb}"); CL_HS+=("$(hs "${kb}")")
    CL_NOTE+=("$(tilde "${p}")"); CL_EXTRA+=("${col}${verb_} $(ago "${days}")${RST}"); CL_DAYS+=("${days}")
    CL_SEL+=(0); CL_DIS+=("")
    # running apps can't be removed
    if [ "${finder}" = find_apps ] && pgrep -f "${p}/Contents/MacOS/" >/dev/null; then CL_DIS[${#CL_DIS[@]}-1]="running"; fi
    # installers are pre-checked: once installed they're dead weight
    case ${finder}:${name} in find_installers:*.dmg|find_installers:*.pkg|find_installers:*.mpkg|find_installers:*.xip) CL_SEL[${#CL_SEL[@]}-1]=1 ;; esac
  done < "${TMPD}/files"

  local n=${#CL_ID[@]}
  if [ ${n} = 0 ]; then
    header; fl ""; fl "  ${GRN}⏺${RST} Nothing found."; wait_enter; return
  fi
  CL_TITLE="${title} · ${n}"
  CL_SUB=${sub}
  CL_KEYS=" · o old"; CL_HOOK=hook_old
  checklist || return
  confirm_screen files || return

  local i sum=0 start ok; start=$(free_kb)
  header; fl ""; show
  live_begin "${start}"
  for ((i=0; i<n; i++)); do
    [ "${CL_SEL[i]}" = 1 ] || continue
    if [ "${MODE}" = trash ]; then
      work "Moving ${CL_LBL[i]} to Trash" to_trash "${CL_ID[i]}"
    else
      work "Deleting ${CL_LBL[i]}" rm -rf "${CL_ID[i]}"
    fi
    if [ -e "${CL_ID[i]}" ]; then
      result "${RED}" "${CL_LBL[i]}" "couldn't remove it · try dragging it to the Trash in Finder"
    elif [ "${MODE}" = trash ]; then
      result "${GRN}" "${CL_LBL[i]}" "${CL_HS[i]} moved to Trash"; sum=$((sum+CL_KB[i]))
    else
      result "${GRN}" "${CL_LBL[i]}" "${CL_HS[i]} freed"; sum=$((sum+CL_KB[i]))
    fi
  done

  if [ "${MODE}" = trash ] && [ ${sum} -gt 0 ]; then
    fl ""
    fl "  ${YLW}?${RST} Files in the Trash still take space. ${BLD}Empty the Trash now?${RST} ${GRY}y = yes · other key = later${RST}"
    show
    if [ "$(key)" = yes ]; then
      work "Emptying the Trash" empty_trash && result "${GRN}" "Trash" "emptied" || result "${RED}" "Trash" "couldn't empty it · do it from Finder"
    else
      printf '  %sOK, empty it later from Finder to get the space back.%s\n' "${GRY}" "${RST}"
    fi
  fi
  live_settle
  summary "${start}" ${sum}
  wait_enter
  live_end
}

large_files() {
  pick_files find_large "Looking for files over ${BIG_MB} MB" "Large files" \
    "files over ${BIG_MB} MB in your home folder · nothing pre-checked · o checks untouched 6+ months" "modified" 180
}

installers() {
  pick_files find_installers "Looking for installers and archives" "Installers & archives" \
    ".dmg/.pkg already installed are dead weight · archives ≥ 50 MB · o checks 1+ month old" "modified" 30
}

unused_apps() {
  pick_files find_apps "Checking when you last used each app" "Apps" \
    "sorted by last use · Apple apps are hidden · o checks unused 6+ months" "used" 180
}

find_nm() {
  local now d kb m proj
  now=$(date +%s)
  find "${HOME}" \( -path "${HOME}/Library" -o -path "${HOME}/.Trash" -o -path "${HOME}/.npm" -o -path "${HOME}/.cache" \) -prune \
       -o -name node_modules -type d -prune -print 2>/dev/null |
  while IFS= read -r d; do
    proj=${d%/node_modules}
    kb=$(kb_of "${d}"); [ -z "${kb}" ] && continue
    # last time the project was touched (newest file, ignoring node_modules)
    m=$(find "${proj}" -maxdepth 2 -path "${d}" -prune -o -type f -print0 2>/dev/null | xargs -0 stat -f %m 2>/dev/null | sort -n | tail -1)
    [ -z "${m}" ] && m=$(stat -f %m "${proj}")
    echo "${kb}|$(( (now-m) / 86400 ))|${d}"
  done | sort -t'|' -k1,1nr > "${TMPD}/nm"
}

node_modules() {
  header; fl ""; show
  work "Looking for node_modules" find_nm
  reset_cl
  OLD_DAYS=90
  local kb days d rel col
  while IFS='|' read -r kb days d; do
    rel=$(tilde "${d%/node_modules}")
    col=${GRY}; [ "${days}" -ge 90 ] && col=${YLW}
    CL_ID+=("${d}"); CL_LBL+=("$(trunc_left "${rel}" ${L})"); CL_KB+=("${kb}"); CL_HS+=("$(hs "${kb}")")
    CL_SEL+=(0); CL_DIS+=(""); CL_NOTE+=("${rel}"); CL_EXTRA+=("${col}touched $(ago "${days}")${RST}"); CL_DAYS+=("${days}")
  done < "${TMPD}/nm"

  local n=${#CL_ID[@]}
  if [ ${n} = 0 ]; then
    header; fl ""; fl "  ${GRN}⏺${RST} No node_modules folders found."; wait_enter; return
  fi
  CL_TITLE="node_modules · ${n} folders"
  CL_SUB="nothing pre-checked · restore with npm install · o checks the ones idle 3+ months"
  CL_KEYS=" · o idle"; CL_HOOK=hook_old
  checklist || return
  confirm_screen || return

  local i sum=0 start; start=$(free_kb)
  header; fl ""; show
  live_begin "${start}"
  for ((i=0; i<n; i++)); do
    [ "${CL_SEL[i]}" = 1 ] || continue
    work "Deleting ${CL_LBL[i]}" rm -rf "${CL_ID[i]}"
    if [ -e "${CL_ID[i]}" ]; then result "${RED}" "${CL_NOTE[i]}" "couldn't delete everything"
    else result "${GRN}" "${CL_NOTE[i]}" "${CL_HS[i]} freed"; sum=$((sum+CL_KB[i])); fi
  done
  live_settle
  summary "${start}" ${sum}
  wait_enter
  live_end
}

# ======================= MENU =======================
MENU_T=("Scan" "Clean" "Large files" "Installers" "Apps" "node_modules" "Quit")
MENU_D=("see what's using your disk"
        "caches, dev tools, Docker, Xcode… safe ones pre-checked"
        "find huge files anywhere in your home folder"
        "old .dmg/.pkg installers and big archives"
        "apps you haven't opened in a long time"
        "dependencies of idle projects"
        "")

menu() {
  local cur=0 k i t n=${#MENU_T[@]}
  while true; do
    header; fl ""
    for ((i=0; i<n; i++)); do
      t=$(pad "${MENU_T[i]}" 14)
      if [ ${i} = ${cur} ]; then fl "  ${ACC}❯${RST} ${BLD}${WHT}${t}${RST} ${GRY}${MENU_D[i]}${RST}"
      else fl "    ${t} ${DIM}${GRY}${MENU_D[i]}${RST}"; fi
    done
    fl ""
    footer "↑↓ move · enter select · 1-${n} shortcut · q quit"
    show
    k=$(key)
    case ${k} in
      up)    cur=$(( (cur-1+n) % n )) ;;
      down)  cur=$(( (cur+1) % n )) ;;
      [1-9]) [ "${k}" -le ${n} ] && { cur=$((k-1)); action ${cur} || return; } ;;
      enter) action ${cur} || return ;;
      quit)  return ;;
    esac
  done
}

action() {
  case ${1} in
    0) scan ;;
    1) clean ;;
    2) large_files ;;
    3) installers ;;
    4) unused_apps ;;
    5) node_modules ;;
    6) return 1 ;;
  esac
  return 0
}

# ======================= START =======================
START_KB=$(free_kb)

on_exit() {
  kill $(jobs -p) 2>/dev/null
  printf '%s' "${E}[r${E}[?25h"; stty echo 2>/dev/null; tput rmcup 2>/dev/null
  local freed=$(( $(free_kb) - START_KB ))
  if [ ${freed} -gt 102400 ]; then
    printf '  %s✻%s Freed this session: %s%s%s · %s free now\n' "${ACC}" "${RST}" "${BLD}" "$(hs ${freed})" "${RST}" "$(hs "$(free_kb)")"
  fi
  rm -rf "${TMPD}"
}
trap on_exit EXIT
trap 'exit 130' INT TERM

tput smcup 2>/dev/null
printf '%s' "${E}[?25l"
stty -echo 2>/dev/null
menu
