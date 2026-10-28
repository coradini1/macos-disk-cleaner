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
# copies of Chrome that pile up when it stays open for days (known Chrome bug)
CHROME_CLONES="$(dirname "$(getconf DARWIN_USER_DIR)")/X/com.google.Chrome.code_sign_clone"
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
    printf '\r  %s%s%s %s%s…%s %s(%ds)%s%s' "${ACC}" "${SPIN[i%10]}" "${RST}" "${WHT}" "${msg}" "${RST}" "${GRY}" $((SECONDS-t0)) "${RST}" "${E}[K"
    i=$((i+1)); sleep 0.08
  done
  printf '\r%s' "${E}[K"
  wait ${pid}
}

result() {   # ⏺ title / ⎿ outcome
  printf '  %s⏺%s %s%s%s\n     %s⎿%s  %s\n' "${1}" "${RST}" "${BLD}${WHT}" "${2}" "${RST}" "${GRY}" "${RST}" "${3}"
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
ITEMS=(chrome_clones chrome_sw caches logs dotcache npm pnpm gradle media vscode apps xcode brew stremio trash)

info() {   # sets NAME DESC SAFE NEEDS_CHROME_CLOSED
  SAFE=1; NEEDS_CHROME_CLOSED=0
  case ${1} in
    chrome_clones) NAME="Chrome leftover copies";      DESC="junk Chrome leaves when it stays open for days"; NEEDS_CHROME_CLOSED=1 ;;
    chrome_sw)     NAME="Chrome Service Worker";       DESC="offline website cache · you stay logged in"; NEEDS_CHROME_CLOSED=1 ;;
    caches)        NAME="App caches";                  DESC="~/Library/Caches · apps rebuild it on their own" ;;
    logs)          NAME="Logs";                        DESC="old app logs" ;;
    dotcache)      NAME="~/.cache";                    DESC="dev tool caches (puppeteer, huggingface…)" ;;
    npm)           NAME="npm cache";                   DESC="downloaded again when needed" ;;
    pnpm)          NAME="pnpm store";                  DESC="only removes packages no project uses" ;;
    gradle)        NAME="Gradle cache";                DESC="Android/Java · downloaded again on next build" ;;
    media)         NAME="macOS photo analysis cache";  DESC="macOS rebuilds it over time" ;;
    vscode)        NAME="VS Code cache";               DESC="rebuilt when VS Code opens" ;;
    apps)          NAME="Discord/Spotify cache";       DESC="cached media and songs" ;;
    xcode)         NAME="Xcode DerivedData";           DESC="temporary Xcode builds" ;;
    brew)          NAME="Homebrew";                    DESC="old package versions and downloads" ;;
    stremio)       NAME="Stremio";                     DESC="cached movies" ;;
    trash)         NAME="Trash";                       DESC="PERMANENT · these are your files"; SAFE=0 ;;
  esac
}

paths() {
  local d
  case ${1} in
    chrome_clones) echo "${CHROME_CLONES}" ;;
    chrome_sw)     for d in "${CHROME}"/Default "${CHROME}"/Profile\ *; do echo "${d}/Service Worker"; done ;;
    caches)        echo "${HOME}/Library/Caches" ;;
    logs)          echo "${HOME}/Library/Logs" ;;
    dotcache)      echo "${HOME}/.cache" ;;
    npm)           echo "${HOME}/.npm" ;;
    pnpm)          d=$(pnpm store path 2>/dev/null); echo "${d:-${HOME}/Library/pnpm}" ;;
    gradle)        printf '%s\n' "${HOME}/.gradle/caches" "${HOME}/.gradle/daemon" "${HOME}/.gradle/wrapper/dists" ;;
    media)         echo "${HOME}/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/com.apple.mediaanalysisd" ;;
    vscode)        printf '%s\n' "${AS}/Code/Cache" "${AS}/Code/CachedData" "${AS}/Code/Code Cache" ;;
    apps)          printf '%s\n' "${AS}/discord/Cache" "${AS}/Spotify/PersistentCache" ;;
    xcode)         echo "${HOME}/Library/Developer/Xcode/DerivedData" ;;
    stremio)       echo "${AS}/stremio-server" ;;
    trash)         echo "${HOME}/.Trash" ;;
  esac
}

# size in KB (-1 = doesn't exist, -2 = no permission to read)
size_of() {
  local id=${1} kb=0 found=0 err=0 p s
  case ${id} in
    npm|pnpm) command -v "${id}" >/dev/null || { echo -1; return; } ;;
    brew)
      command -v brew >/dev/null || { echo -1; return; }
      brew cleanup -n -s --prune=all 2>/dev/null | awk '
        match($0, /approximately [0-9.]+[KMG]?B/) {
          s = substr($0, RSTART+14, RLENGTH-14); n = s + 0
          if (s ~ /GB/) n *= 1048576; else if (s ~ /MB/) n *= 1024; else if (s !~ /KB/) n /= 1024
          printf "%d\n", n; f = 1 }
        END { if (!f) print 0 }'
      return ;;
  esac
  while IFS= read -r p; do
    [ -e "${p}" ] || continue
    found=1
    s=$(du -sk "${p}" 2>/dev/null | awk '{print $1}')
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

clean_item() {
  local p rc=0
  case ${1} in
    npm)  npm cache clean --force >/dev/null 2>&1 || rc=1 ;;
    pnpm) pnpm store prune >/dev/null 2>&1 || rc=1 ;;
    brew) brew cleanup -s --prune=all >/dev/null 2>&1 || rc=1 ;;
    chrome_sw|gradle)
      while IFS= read -r p; do
        [ -e "${p}" ] || continue
        rm -rf "${p}" 2>/dev/null; [ -e "${p}" ] && rc=1
      done < <(paths "${1}") ;;
    *)
      while IFS= read -r p; do
        [ -d "${p}" ] || continue
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
           "Pictures|${HOME}/Pictures" "Movies|${HOME}/Movies" \
           "WhatsApp media|${HOME}/Library/Group Containers/group.net.whatsapp.WhatsApp.shared" \
           "iOS Simulators|${HOME}/Library/Developer/CoreSimulator" \
           "Xcode Archives|${HOME}/Library/Developer/Xcode/Archives" \
           "Downloaded macOS update|/Library/Updates"; do
    p=${a#*|}; [ -e "${p}" ] || continue
    kb=$(du -sk "${p}" 2>/dev/null | awk '{print $1}')
    echo "${kb:--2}|${a%%|*}|M" >> "${TMPD}/scan"
  done
}

# ======================= CHECKLIST =======================
# Uses: CL_ID CL_LBL CL_KB CL_HS CL_SEL CL_DIS CL_NOTE CL_EXTRA, CL_TITLE CL_SUB CL_KEYS CL_HOOK
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
    fl "  ${GRY}${CL_SUB}${RST}"
    if [ ${off} -gt 0 ]; then fl "    ${GRY}↑ ${off} more${RST}"; else fl ""; fi
    for ((i=off; i<n && i<off+rows; i++)); do item_row ${i} ${cur} ${max}; done
    if [ $((n-off-rows)) -gt 0 ]; then fl "    ${GRY}↓ $((n-off-rows)) more${RST}"; else fl ""; fi
    note=${CL_NOTE[cur]}
    [ "${CL_DIS[cur]}" = "Chrome is open" ] && note="quit Chrome with Cmd+Q, then press r"
    fl "  ${GRY}⎿  $(trunc "${note}" $((W-7)))${RST}"
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

confirm_screen() {
  local n=${#CL_LBL[@]} i cnt=0 tot=0 trash=0 lim=$((LINES_-16))
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
  fl "  Total ${BLD}~$(hs ${tot})${RST} · ${BLD}Confirm?${RST}  ${GRY}y = yes · any other key cancels${RST}"
  show
  [ "$(key)" = yes ]
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
  lim=$((LINES_-16)); bw=$((W-L-30))
  fl ""; fl "  ${BLD}${WHT}What's using your disk${RST}"; fl ""
  for ((i=0; i<n && i<lim; i++)); do
    if [ "${kind[i]}" = C ]; then tag="${GRN}● cleanable${RST}"; col=${ACC}; else tag="${GRY}○ your call${RST}"; col=${GRY}; fi
    fl "  $(pad "$(trunc "${name[i]}" ${L})" ${L}) ${BLD}$(lpad "$(hs "${kb[i]}")" 9)${RST}  $(bar "${kb[i]}" ${max} ${bw} "${col}") ${tag}"
  done
  [ ${n} -gt ${lim} ] && fl "  ${GRY}… and $((n-lim)) more${RST}"
  fl ""
  fl "  ${ACC}✻${RST} You can free ${BLD}~$(hs ${sum})${RST} with ${BLD}Clean${RST}"
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
  CL_ID=(); CL_LBL=(); CL_KB=(); CL_HS=(); CL_SEL=(); CL_DIS=(); CL_NOTE=(); CL_EXTRA=()
  local id kb open=0 note
  chrome_open && open=1
  while read -r id kb; do
    [ "${kb}" = -1 ] && continue
    [ "${kb}" -ge 0 ] && [ "${kb}" -lt 1024 ] && continue
    info "${id}"
    note=${DESC}; [ "${kb}" = -2 ] && note="no permission to read · give your terminal Full Disk Access"
    CL_ID+=("${id}"); CL_LBL+=("${NAME}"); CL_KB+=("${kb}"); CL_HS+=("$(hs "${kb}")"); CL_NOTE+=("${note}"); CL_EXTRA+=("")
    if [ ${NEEDS_CHROME_CLOSED} = 1 ] && [ ${open} = 1 ]; then CL_DIS+=("Chrome is open"); CL_SEL+=(0)
    else CL_DIS+=(""); CL_SEL+=("${SAFE}"); fi
  done < "${TMPD}/sizes"

  if [ ${#CL_ID[@]} = 0 ]; then
    header; fl ""; fl "  ${GRN}⏺${RST} Nothing to clean, you're all set."; wait_enter; return
  fi
  CL_TITLE="What to delete"
  CL_SUB="checked items are safe, the system rebuilds them · Trash is never pre-checked"
  CL_KEYS=""; [ ${open} = 1 ] && CL_KEYS=" · r refresh"
  CL_HOOK=hook_chrome
  checklist || return
  confirm_screen || return

  local n=${#CL_ID[@]} i before after freed rc sum=0 start
  start=$(free_kb)
  header; fl ""; show
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
  sleep 1
  summary "${start}" ${sum}
  wait_enter
}

find_nm() {
  local now d kb m proj
  now=$(date +%s)
  find "${HOME}" \( -path "${HOME}/Library" -o -path "${HOME}/.Trash" -o -path "${HOME}/.npm" -o -path "${HOME}/.cache" \) -prune \
       -o -name node_modules -type d -prune -print 2>/dev/null |
  while IFS= read -r d; do
    proj=${d%/node_modules}
    kb=$(du -sk "${d}" 2>/dev/null | awk '{print $1}'); [ -z "${kb}" ] && continue
    # last time the project was touched (newest file, ignoring node_modules)
    m=$(find "${proj}" -maxdepth 2 -path "${d}" -prune -o -type f -print0 2>/dev/null | xargs -0 stat -f %m 2>/dev/null | sort -n | tail -1)
    [ -z "${m}" ] && m=$(stat -f %m "${proj}")
    echo "${kb}|$(( (now-m) / 86400 ))|${d}"
  done | sort -t'|' -k1,1nr > "${TMPD}/nm"
}

hook_old() {
  [ "${1}" = old ] || return 0
  local i
  for ((i=0; i<${#CL_ID[@]}; i++)); do [ "${CL_DAYS[i]}" -ge 90 ] && CL_SEL[i]=1; done
}

node_modules() {
  header; fl ""; show
  work "Looking for node_modules" find_nm
  CL_ID=(); CL_LBL=(); CL_KB=(); CL_HS=(); CL_SEL=(); CL_DIS=(); CL_NOTE=(); CL_EXTRA=(); CL_DAYS=()
  local kb days d rel col
  while IFS='|' read -r kb days d; do
    rel="~${d#${HOME}}"; rel=${rel%/node_modules}
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
  for ((i=0; i<n; i++)); do
    [ "${CL_SEL[i]}" = 1 ] || continue
    work "Deleting ${CL_LBL[i]}" rm -rf "${CL_ID[i]}"
    if [ -e "${CL_ID[i]}" ]; then result "${RED}" "${CL_NOTE[i]}" "couldn't delete everything"
    else result "${GRN}" "${CL_NOTE[i]}" "${CL_HS[i]} freed"; sum=$((sum+CL_KB[i])); fi
  done
  sleep 1
  summary "${start}" ${sum}
  wait_enter
}

menu() {
  local cur=0 k i t
  local OT=("Scan" "Clean" "node_modules" "Quit")
  local OD=("see what's using your disk" "pick what to delete · safe caches pre-checked" "delete dependencies of idle projects" "")
  while true; do
    header; fl ""
    for ((i=0; i<4; i++)); do
      t=$(pad "${OT[i]}" 14)
      if [ ${i} = ${cur} ]; then fl "  ${ACC}❯${RST} ${BLD}${WHT}${t}${RST} ${GRY}${OD[i]}${RST}"
      else fl "    ${t} ${DIM}${GRY}${OD[i]}${RST}"; fi
    done
    fl ""
    footer "↑↓ move · enter select · 1-4 shortcut · q quit"
    show
    k=$(key)
    case ${k} in
      up)    cur=$(( (cur+3) % 4 )) ;;
      down)  cur=$(( (cur+1) % 4 )) ;;
      [1-4]) cur=$((k-1)); action ${cur} || return ;;
      enter) action ${cur} || return ;;
      quit)  return ;;
    esac
  done
}

action() {
  case ${1} in
    0) scan ;;
    1) clean ;;
    2) node_modules ;;
    3) return 1 ;;
  esac
  return 0
}

# ======================= START =======================
START_KB=$(free_kb)

on_exit() {
  kill $(jobs -p) 2>/dev/null
  printf '%s' "${E}[?25h"; stty echo 2>/dev/null; tput rmcup 2>/dev/null
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
