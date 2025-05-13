#! /bin/bash

readonly USAGE="Automated version management and release publishing (in bash).
Usage:
  gitple [command]

Available Commands:
  create          Crea una plantilla para un nuevo proyecto.
  delete-tag      Elimina una tag.
  delete-branch   Elimina una branch.
  new-version     Sube de versión tu aplicación de forma automática dependiendo de tus commits.
  version         Te dice la última versión de tu aplicación.

Flags:
  -h, --help      Show this help."

readonly SEMANTIC_RELEASE_VERSION="0.1.0"

readonly ERROR_MISSING_DEPS=1
readonly ERROR_ARGUMENTS=2
readonly ERROR_INVALID_REPOSITORY=3
readonly ERROR_GIT=4

readonly SEMVER_PATTERN="^v([0-9]+)\.([0-9]+)\.([0-9]+)$"
readonly FIX_PATTERN="^fix[:\(]"
readonly FEAT_PATTERN="^feat(\(.*\))?:"
readonly SUBJECT_PATTERN="^(feat|fix|docs|style|refactor|test|chore|perf)(\(.*\))?:"
readonly BREAKING_PATTERN="^BREAKING(\(.*\))?:"
readonly CLOSES_PATTERN="^closes\s(.+)"

readonly NO_BUMP=0
readonly PATCH_BUMP=1
readonly FEATURE_BUMP=2
readonly BREAKING_BUMP=3

dry_run=0
commit_messages=()
bump_type=$NO_BUMP
version=""
last_release_tag="" 
release_notes=""

# Variables de entorno para conexión con github
GITHUB_OWNER="carlitooos1223"
GITHUB_REPO=gitate

shopt -s extglob

options() {
        if [ $# -eq 0 ]; then
                echo "$USAGE"
                exit
        fi

        while :; do
		case $1 in
                        new-version)
                                semantic_release "${BASH_ARGV[@]}"
                                exit
                                ;;
                        version)
                                echo "Semantic-release: v${SEMANTIC_RELEASE_VERSION}"
                                exit
                                ;;
                        -h|-\?|--help)
                                echo "$USAGE"
                                exit
                                ;;
                        -?*)
                                echo "Comando desconocido: $1" >&2
                                echo "$USAGE"
                                exit "$ERROR_ARGUMENTS"
                                ;;
                        ?*)
                                echo "Comando desconocido: $1" >&2
                                echo "$USAGE"
                                exit "$ERROR_ARGUMENTS"
                                ;;
                esac
                shift
        done
}

check_dependencies() {
  for cmd in "$@"; do
    if ! command -v "$cmd" > /dev/null ; then
      echo "$cmd command not found"
      exit $ERROR_MISSING_DEPS
    fi
  done
}

find_last_release_tag() {
  local tags sorted
  tags=()
  if ! output=$(git tag --sort=-v:refname 2>&1); then
    echo "Not a git repository" >&2
    exit $ERROR_INVALID_REPOSITORY
  fi

  while read -r tag ; do
    if [[ "$tag" =~ $SEMVER_PATTERN ]] &&
      git merge-base --is-ancestor "$tag" HEAD 2>/dev/null; then 
      tags+=("$tag")
    fi
  done <<< "$output"

  if [[ ${#tags[@]} -eq 0 ]]; then
    echo "No se encontró ninguna etiqueta, estableciendo v0.1.0"
    last_release_tag="v0.1.0"
  else
    last_release_tag="${tags[0]}"
  fi
}

read_commit_messages() {
  local from range
  from="$1"
  commit_messages=()

  if [[ -z "$from" || "$from" == "v0.1.0" ]]; then 
    from=$(git rev-list --max-parents=0 HEAD)
    range="${from}..HEAD"
  else
    from=$(git rev-parse "$from") 
    range="${from}..HEAD"
  fi

  while IFS=$'\x1f' read -r -d $'\x1e' commit_id commit; do
    commit=${commit%%$'\n'}
    commit=${commit##$'\n'} 
    commit_messages+=("${commit} ${commit_id}")
  done < <(git log --pretty=format:'%h%x1f%B%x1e' "$range")
}

declare -A categorized_changes=(
  [feat]=""
  [fix]=""
  [docs]=""
  [style]=""
  [refactor]=""
  [test]=""
  [chore]=""
  [perf]=""
  [breaking]=""
)

append_changelog() {
  local commit first subject refs closes type 
  commit="$1"
  commit_id="$2"
  first=1
  refs=()

  while read -r line ; do
    if [[ "$first" -eq 1 ]]; then
      subject="$line"
      if [[ "$subject" =~ $SUBJECT_PATTERN ]]; then
        type="${BASH_REMATCH[1]}"
      else
        type="other"
      fi
    fi

    if [[ "$first" -ne 1 ]] && [[ "${line,,}" =~ $CLOSES_PATTERN ]]; then
      IFS=', '
      read -r -a array <<< "${BASH_REMATCH[1]}"
      refs+=("${array[@]}")
    fi

    first=0
  done <<< "$commit"

  if [[ ${#refs[@]} -ne 0 ]]; then
    IFS=','; closes=" (${refs[*]})"
  else
    closes=""
  fi

  type=${type,,}
  categorized_changes[$type]+="$subject$closes\n"
}

update_bump_type() {
  local commit bump first
  commit="$1"
  bump=$NO_BUMP
  first=1

  while read -r line; do
    if [[ "$first" -eq 1 ]] && [[ "$line" =~ $FIX_PATTERN ]]; then
      bump=$PATCH_BUMP
    fi
    if [[ "$first" -eq 1 ]] && [[ "$line" =~ $FEAT_PATTERN ]]; then
        bump=$FEATURE_BUMP
    fi
    if [[ "$first" -eq 1 ]] && [[ "$line" =~ $BREAKING_PATTERN ]]; then
        bump=$BREAKING_BUMP
    fi
    first=0
  done <<< "$commit"

  if [[ "$bump" -gt "$bump_type" ]]; then
    bump_type="$bump"
  fi
}

analyze_commit_messages() {
  declare -gA categorized_changes=(
    [feat]=""
    [fix]=""
    [docs]=""
    [style]=""
    [refactor]=""
    [test]=""
    [chore]=""
    [perf]=""
    [BREAKING]=""
  )
  bump_type=$NO_BUMP

  for commit_message in "$@" ; do
    commit_id=$(echo $commit_message | cut -d' ' -f2)
    commit=$(echo $commit_message | cut -d' ' -f1-)
    append_changelog "$commit" $commit_id
    update_bump_type "$commit_message"
  done
}

bump_version() {
  local bump last_version major minor patch
  bump="$1"
  last_version="$2"
  version=""

  if [[ "$last_version" =~ $SEMVER_PATTERN ]] ; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
    if [[ "$bump" == "$PATCH_BUMP" ]] ; then
      patch=$((patch+1))
    fi
    if [[ "$bump" == "$FEATURE_BUMP" ]] ; then
      minor=$((minor+1))
      patch=0
    fi
    if [[ "$bump" == "$BREAKING_BUMP" ]] ; then
      major=$((major+1))
      minor=0
      patch=0
    fi
    version="v${major}.${minor}.${patch}"
  fi
}

build_release_notes() {
  release_notes=""
  for type in feat fix docs style refactor test chore perf; do
    local entries="${categorized_changes[$type]}"
    if [[ -n "$entries" ]]; then
      release_notes+="### ${type^}\n"
      while IFS= read -r line; do
        [[ -n "$line" ]] && release_notes+="* $line\n"
      done <<< "$(echo -e "$entries")"
      release_notes+="\n"
    fi
  done
  release_notes=${release_notes//$'\n'/\\n}
  release_notes=${release_notes//\"/\\\"}
}

create_gitlab_tag() {
  local githead data base_url url outfile status
  githead=$(git rev-parse HEAD)
  data="{
    \"tag_name\": \"${version}\",
    \"ref\": \"${githead}\",
    \"message\": \"Semantic release ${version}\",
    \"release_description\": \"${release_notes}\",
    \"draft\": false,
    \"prerelease\": false
  }"
  base_url=${$GITHUB_OWNER/$GITHUB_REPO/}
  url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/git/refs"

  outfile=$(mktemp)
  trap '{ rm -f "$outfile"; }' EXIT

  if ! status=$(curl \
    --silent \
    --show-error \
    --output "$outfile" \
    --write-out $'%{http_code}' \
    --header "PRIVATE-TOKEN: ${GITHUB_TOKEN}" \
    --header "Content-Type: application/json" \
    --data "$data" \
    "$url") || [[ "$status" -ge 300 ]]; then
    echo "Error creating tag on GITLAB:" >&2
    echo "curl exit code: $?" >&2
    echo "HTTP Status: $status" >&2
    echo "HTTP Request:" >&2
    echo "$data"
    echo "HTTP Response:" >&2
    cat "$outfile" >&2
    echo
    exit "$ERROR_GIT"
  fi
  echo "Tag created on GITLAB"
}

create_git_tag() {
  local output
  if ! output=$(git tag -m "Semantic release $version" "$version"); then
    echo "Error creating tag in local git repository:" >&2
    echo "git exit code: $?" >&2
    echo "git output:" >&2
    echo "$output" >&2
    exit "$ERROR_GIT"
  fi
  echo "Tag created in local git repository" >&2
}

create_tag() {
  if [[ -n $GITHUB_TOKEN ]]; then
    create_gitlab_tag
    create_gitlab_release
  else
    echo "Environment variable GITHUB_TOKEN not provided." >&2
    create_git_tag
  fi
}

get_versions() {
  declare -A versions
  local tag major minor patch

  for tag in $(git tag --sort=-v:refname); do
    if [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
      major="${BASH_REMATCH[1]}"
      minor="${BASH_REMATCH[2]}"
      patch="${BASH_REMATCH[3]}"

      versions["$major,$minor"]="$tag"
    fi
  done

  echo "${!versions[@]}"
}

semantic_release() {
  check_dependencies git curl
  find_last_release_tag
  read_commit_messages "$last_release_tag"
  analyze_commit_messages "${commit_messages[@]}"

  if [[ "$bump_type" -eq "$NO_BUMP" ]]; then
    echo "No changes since last release" >&2 
    return
  else
    if [[ -z "$last_release_tag" ]]; then
      version="v0.1.0"
    else
      bump_version "$bump_type" "$last_release_tag"
    fi
    build_release_notes 

    date=$(date "+%Y-%m-%d")

    # Create necessary files
    if [ ! -d "info" ]; then
      mkdir info
    fi
    touch info/app_version.txt
    touch info/last_version.txt
    touch info/new_version.txt
    touch info/title.txt

    url_versiones="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/tree"

    # Create the changelog
    echo -e "# CHANGELOG \nAll notable changes to this project will be documented in this file." > info/title.txt
    echo -e "## [$version]($url_versiones/$version) - $date\n" | tee info/new_version.txt
    echo -e "$(echo -e "$release_notes")" | tee -a info/new_version.txt

    cat info/new_version.txt info/app_version.txt > temp && mv temp info/app_version.txt 
    cat info/title.txt info/app_version.txt > CHANGELOG.md

    echo $version > info/last_version.txt

    # Create the new tag in the local repository
    if ! git tag | grep "^$version" ; then
      git tag $version;
      echo "Tag $version creado";
    else
      echo "Tag $version ya existe, no se hace nada"; 
    fi

    bump_version "$bump_type" "$last_release_tag"

    if [[ "$dry_run" -eq 1 ]]; then
      echo "Dry run. Tag not created."
    else
      create_tag
    fi
  fi
}

options "$@"