#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}

cd "$REPO_ROOT"

fail() {
    printf '[docs-check][error] %s\n' "$1" >&2
    exit 1
}

info() {
    printf '[docs-check] %s\n' "$1"
}

check_file() {
    local file="$1"
    [[ -f "$file" ]] || fail "Required file is missing: $file"
}

check_contains() {
    local file="$1"
    local needle="$2"
    grep -Fq -- "$needle" "$file" || fail "$file is missing required text: $needle"
}

check_markdown_links() {
    if ! command -v perl >/dev/null 2>&1; then
        fail "perl is required for local Markdown link validation"
    fi

    local files=()
    local file
    local source
    local link
    local target
    local candidate

    while IFS= read -r file; do
        files+=("$file")
    done < <(
        {
            printf '%s\n' README.md README.zh-CN.md CHANGELOG.md llms.txt \
                docs/FAQ.md docs/项目快贴-PRD.md docs/ai-search/llms-full.txt \
                .github/CONTRIBUTING.md .github/SECURITY.md .github/CODE_OF_CONDUCT.md
            find docs .github -type f \( -name '*.md' -o -name '*.yml' -o -name '*.yaml' \) -print
        } | sort -u
    )

    while IFS=$'\t' read -r source link; do
        [[ -n "$source" && -n "$link" ]] || continue

        link="${link#<}"
        link="${link%>}"
        case "$link" in
            http://*|https://*|mailto:*|\#*)
                continue
                ;;
        esac

        target="${link%%#*}"
        [[ -n "$target" ]] || continue

        if [[ "$target" == /* ]]; then
            fail "Markdown link in $source uses an absolute local path: $link"
        fi

        candidate="${source:h}/${target}"
        [[ -e "$candidate" ]] || fail "Broken Markdown link in $source: $link"
    done < <(
        perl -0ne '
            while (/!?\[[^\]]*\]\(([^)\s]+(?:\s+"[^"]*")?)\)/g) {
                my $link = $1;
                $link =~ s/\s+"[^"]*"$//;
                print "$ARGV\t$link\n";
            }
        ' "${files[@]}"
    )
}

required_files=(
    "README.md"
    "README.zh-CN.md"
    "docs/FAQ.md"
    "docs/项目快贴-PRD.md"
    ".github/CONTRIBUTING.md"
    ".github/SECURITY.md"
    ".github/CODE_OF_CONDUCT.md"
    "CHANGELOG.md"
    "LICENSE"
    "llms.txt"
    "docs/ai-search/llms-full.txt"
    "codemeta.json"
    "docs/README.md"
    "docs/项目介绍.md"
    "docs/架构说明.md"
    "docs/关键模块与核心逻辑.md"
    "docs/API与功能说明.md"
    "docs/配置说明.md"
    "docs/部署说明.md"
    "docs/开发规范.md"
    "docs/使用示例.md"
    "docs/运维与排错指南.md"
    "docs/生产发布与恢复手册.md"
    "docs/路线图与贡献指南.md"
    "docs/ai-search-discoverability.md"
    "docs/search-metadata.schema.jsonld"
    "docs/文档与代码同步矩阵.md"
    "docs/接手维护指南.md"
    "openspec/specs/project-documentation/spec.md"
    "openspec/changes/complete-project-docs/proposal.md"
    "openspec/changes/complete-project-docs/tasks.md"
    "openspec/changes/complete-project-docs/specs/project-documentation/spec.md"
)

info "Checking required public documentation files"
for file in "${required_files[@]}"; do
    check_file "$file"
done

info "Checking documentation navigation"
index_links=(
    "docs/项目介绍.md"
    "docs/API与功能说明.md"
    "docs/开发规范.md"
    "docs/使用示例.md"
    "docs/路线图与贡献指南.md"
    "docs/ai-search-discoverability.md"
    "docs/search-metadata.schema.jsonld"
)

for link in "${index_links[@]}"; do
    check_contains "README.md" "$link"
    check_contains "README.zh-CN.md" "$link"
done

docs_index_links=(
    "./项目介绍.md"
    "./API与功能说明.md"
    "./开发规范.md"
    "./使用示例.md"
    "./路线图与贡献指南.md"
    "./ai-search-discoverability.md"
    "./search-metadata.schema.jsonld"
)

for link in "${docs_index_links[@]}"; do
    check_contains "docs/README.md" "$link"
done

info "Checking AI-search and metadata entry points"
metadata_needles=(
    "PromptPanel"
    "macOS prompt manager"
    "local-first prompt library"
    "ChatGPT prompt manager"
    "Claude prompt library"
    "Cursor snippet manager"
)

for needle in "${metadata_needles[@]}"; do
    check_contains "llms.txt" "$needle"
    check_contains "docs/ai-search/llms-full.txt" "$needle"
    check_contains "docs/ai-search-discoverability.md" "$needle"
    check_contains "codemeta.json" "$needle"
done

check_contains "docs/search-metadata.schema.jsonld" "SoftwareApplication"
check_contains "docs/search-metadata.schema.jsonld" "SoftwareSourceCode"
check_contains "docs/ai-search-discoverability.md" "llms.txt"
check_contains "docs/ai-search-discoverability.md" "Schema.org"
check_contains ".github/CONTRIBUTING.md" "./scripts/check-docs.sh"
check_contains "docs/开发规范.md" "./scripts/check-docs.sh"
check_contains "docs/文档与代码同步矩阵.md" "./scripts/check-docs.sh"
check_contains ".github/workflows/macos-release-readiness.yml" "scripts/check-docs.sh"
check_contains "scripts/release-readiness.sh" "scripts/check-docs.sh"
check_contains "docs/README.md" "../openspec/specs/project-documentation/spec.md"
check_contains "docs/README.md" "../openspec/changes/complete-project-docs/proposal.md"
check_contains "docs/开发规范.md" "openspec/changes/<change-id>"
check_contains "docs/接手维护指南.md" "openspec/changes/"
check_contains "openspec/specs/project-documentation/spec.md" "Maintainer Documentation Coverage"
check_contains "openspec/changes/complete-project-docs/tasks.md" 'Update `docs/README.md`'

if [[ -x /usr/libexec/PlistBuddy ]]; then
    app_short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/PromptPanel/Resources/Info.plist)"
    check_contains "codemeta.json" "\"version\": \"$app_short_version\""
    check_contains "docs/search-metadata.schema.jsonld" "\"softwareVersion\": \"$app_short_version\""

    # Minimum macOS version must agree across the three surfaces that promise it. Drift here
    # would let a build claim 14.0 in Info.plist while documentation says otherwise.
    info_plist_min_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Sources/PromptPanel/Resources/Info.plist)"
    info_plist_major="${info_plist_min_macos%%.*}"
    if ! grep -Fq ".macOS(.v${info_plist_major})" Package.swift; then
        fail "Package.swift platform does not match Info.plist LSMinimumSystemVersion ($info_plist_min_macos); expected .macOS(.v${info_plist_major})"
    fi
    if ! grep -Fq "macOS ${info_plist_major}+" README.md; then
        fail "README.md is missing the 'macOS ${info_plist_major}+' claim that matches Info.plist LSMinimumSystemVersion ($info_plist_min_macos)"
    fi
    if ! grep -Fq "macOS ${info_plist_major}+" README.zh-CN.md; then
        fail "README.zh-CN.md is missing the 'macOS ${info_plist_major}+' claim that matches Info.plist LSMinimumSystemVersion ($info_plist_min_macos)"
    fi
else
    printf '[docs-check][warn] PlistBuddy is unavailable; skipped app version metadata alignment\n' >&2
fi

info "Checking script and environment documentation coverage"
top_level_scripts=(
    "scripts/build-app.sh"
    "scripts/release-readiness.sh"
    "scripts/restore-backup.sh"
    "scripts/notarize-app.sh"
    "scripts/launch-computer-use.sh"
    "scripts/capture-ui-qa.sh"
    "scripts/check-docs.sh"
)

for script in "${top_level_scripts[@]}"; do
    if ! grep -R -Fq -- "$script" README.md README.zh-CN.md docs .github; then
        fail "Maintenance script is not documented: $script"
    fi
done

while IFS= read -r env_name; do
    [[ -n "$env_name" ]] || continue
    if ! grep -R -Fq -- "$env_name" docs/配置说明.md docs/API与功能说明.md docs/运维与排错指南.md docs/接手维护指南.md docs/文档与代码同步矩阵.md; then
        fail "PROMPTPANEL environment variable is not documented: $env_name"
    fi
done < <(grep -RohE 'PROMPTPANEL_[A-Z0-9_]+' Sources scripts | sort -u)

info "Linting structured metadata JSON"
json_files=(
    "codemeta.json"
    "docs/search-metadata.schema.jsonld"
)

for file in "${json_files[@]}"; do
    if command -v python3 >/dev/null 2>&1; then
        python3 -m json.tool "$file" >/dev/null || fail "Invalid JSON metadata: $file"
    elif command -v plutil >/dev/null 2>&1; then
        plutil -lint "$file" >/dev/null || fail "Invalid JSON metadata: $file"
    else
        printf '[docs-check][warn] No JSON linter available; skipped %s\n' "$file" >&2
    fi
done

info "Checking for stale public documentation terms"
stale_scan_files=(
    "README.md"
    "README.zh-CN.md"
    "docs/FAQ.md"
    ".github/CONTRIBUTING.md"
    "llms.txt"
    "docs/ai-search/llms-full.txt"
    "docs/README.md"
    "docs/项目介绍.md"
    "docs/架构说明.md"
    "docs/关键模块与核心逻辑.md"
    "docs/API与功能说明.md"
    "docs/配置说明.md"
    "docs/部署说明.md"
    "docs/开发规范.md"
    "docs/使用示例.md"
    "docs/运维与排错指南.md"
    "docs/生产发布与恢复手册.md"
    "docs/路线图与贡献指南.md"
    "docs/ai-search-discoverability.md"
    "docs/接手维护指南.md"
)

stale_pattern='promptpanel\.sqlite|四个迁移|Option Space|⌥Space|缺少 xctest.*测试已执行|/Users/xiaomo|Linux 容器运行产品 \| 支持|普通服务器运行产品 \| 支持'
if grep -n -E "$stale_pattern" "${stale_scan_files[@]}" >/tmp/promptpanel-docs-stale.$$ 2>/dev/null; then
    cat /tmp/promptpanel-docs-stale.$$ >&2
    rm -f /tmp/promptpanel-docs-stale.$$
    fail "Stale documentation terms found"
fi
rm -f /tmp/promptpanel-docs-stale.$$

info "Checking local Markdown links"
check_markdown_links

info "Documentation checks passed"
