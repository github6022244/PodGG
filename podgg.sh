#!/bin/bash
# 定义颜色常量
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
NC=$(tput sgr0)  # 重置颜色

# 重试配置
MAX_RETRIES=3
RETRY_DELAY=5  # 秒
POD_REPO_RETRIES=5  # CDN更新额外增加重试次数

# 测试模式开关，默认关闭
TEST_MODE=0

# 核心默认配置（使用master作为默认分支）
DEFAULT_VERSION="0.1.0"
DEFAULT_BRANCH="master"

# 测试模式默认数据
TEST_POD_NAME="GGTestPods"
TEST_SOURCE_URL="git@gitee.com:6022463/GGTestPods.git"

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 验证版本号格式
validate_and_clean_version() {
    local raw_version="$1"
    local cleaned_version=$(echo "$raw_version" | cut -d'#' -f1 | xargs)
    if ! [[ "$cleaned_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf "%b错误：版本号格式无效 - %s%b\n" "$RED" "$cleaned_version" "$NC"
        printf "%b版本号必须符合语义化规范（x.y.z）%b\n" "$YELLOW" "$NC"
        return 1
    fi
    echo "$cleaned_version"
    return 0
}

# 验证Pod是否已上传成功（通过查询trunk）
verify_pod_upload() {
    local pod_name="$1"
    local version="$2"
    printf "%b正在验证Pod是否上传成功...%b\n" "$BLUE" "$NC"
    # 重试查询3次
    for i in {1..3}; do
        # 查询trunk上的版本信息
        if pod trunk info "$pod_name" | grep -q "$version"; then
            return 0  # 验证成功
        fi
        sleep 2
    done
    return 1  # 验证失败
}

# 获取Git仓库根目录
get_git_root() {
    local root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$root" ] && [ -d "$root/.git" ]; then
        echo "$root"
        return 0
    fi
    return 1
}

# 确保在Git仓库中执行命令
ensure_in_git_repo() {
    local command_name="$1"
    if ! get_git_root >/dev/null; then
        printf "%b错误：执行 %s 命令需要在Git仓库中%b\n" "$RED" "$command_name" "$NC"
        printf "%b请先进入一个Git仓库目录，或使用 create 命令创建新仓库%b\n" "$YELLOW" "$NC"
        exit 1
    fi
}

# 带重试机制的命令执行函数
retry_command() {
    local cmd="$1"
    local description="$2"
    local retries=${3:-$MAX_RETRIES}  # 允许指定重试次数
    local exit_code=0
    while [ $retries -gt 0 ]; do
        printf "%b%s...%b\n" "$BLUE" "$description" "$NC"
        if eval "$cmd"; then
            printf "%b%s成功%b\n" "$GREEN" "$description" "$NC"
            return 0
        fi
        exit_code=$?
        retries=$((retries - 1))
        printf "%b%s失败（错误码: %d）%b\n" "$YELLOW" "$description" "$exit_code" "$NC"
        if [ $retries -gt 0 ]; then
            printf "%b将在%d秒后重试（剩余%d次）%b\n" "$YELLOW" "$RETRY_DELAY" "$retries" "$NC"
            sleep $RETRY_DELAY
        fi
    done
    printf "%b%s失败，已达到最大重试次数%b\n" "$RED" "$description" "$NC"
    return $exit_code
}

# 检查并更新CocoaPods仓库
update_cocoapods_repo() {
    printf "\n%b【更新CocoaPods仓库】%b\n" "$BLUE" "$NC"
    # 先尝试更新trunk仓库
    if ! retry_command "pod repo update trunk" "更新trunk仓库" $POD_REPO_RETRIES; then
        printf "%b警告：trunk仓库更新失败，尝试切换CDN源%b\n" "$YELLOW" "$NC"
        # 切换到旧的git源
        if pod repo list | grep -q "trunk"; then
            pod repo remove trunk
        fi
        # 添加非CDN的trunk源
        if ! retry_command "pod repo add trunk https://github.com/CocoaPods/Specs.git" "添加传统trunk源" $POD_REPO_RETRIES; then
            printf "%b错误：无法更新CocoaPods仓库，可能影响上传%b\n" "$RED" "$NC"
            read -p "是否继续上传？(y/n): " continue_upload
            if [ "$continue_upload" != "y" ] && [ "$continue_upload" != "Y" ]; then
                exit 1
            fi
        fi
    fi
}

# 检查是否安装了必要工具
check_dependencies() {
    local dependencies=("pod" "git" "tput" "sed")
    for dep in "${dependencies[@]}"; do
        if ! command_exists "$dep"; then
            printf "%b错误：未安装 %s，请先安装后再运行脚本%b\n" "$RED" "$dep" "$NC"
            exit 1
        fi
    done
}

# 带测试模式支持的输入函数
read_with_test() {
    local prompt="$1"
    local var_name="$2"
    local default_value="$3"
    local test_value="$4"
    if [ "$TEST_MODE" -eq 1 ]; then
        printf "%b测试模式: %s -> 使用预设值: %s%b\n" "$YELLOW" "$prompt" "$test_value" "$NC"
        eval "$var_name='$test_value'"
        return
    fi
    if [ -n "$default_value" ]; then
        read -p "$prompt [默认: $default_value]: " input
        input=${input:-$default_value}
    else
        read -p "$prompt: " input
    fi
    eval "$var_name='$input'"
}

# 配置Git远程仓库
configure_git_remote() {
    local git_url="$1"
    local branch_name="$2"
    local target_dir="$3"
    local pod_name="$4"
    printf "\n%b【Git仓库配置】%b\n" "$BLUE" "$NC"
    # 自动配置Git，不询问（简化流程）
    auto_config="y"
    if [ "$auto_config" != "y" ] && [ "$auto_config" != "Y" ]; then
        printf "%b已选择手动配置Git%b\n" "$YELLOW" "$NC"
        printf "1. 进入项目目录: cd %s\n" "$target_dir"
        printf "2. 初始化Git仓库: git init\n"
        printf "3. 添加远程仓库: git remote add origin %s\n" "$git_url"
        printf "4. 创建并切换到分支: git checkout -b %s\n" "$branch_name"
        printf "5. 推送代码: git push -u origin %s\n" "$branch_name"
        return 0
    fi
    # 自动配置
    cd "$target_dir" || exit 1
    # 初始化Git仓库（如果未初始化）
    if [ ! -d ".git" ]; then
        git init
        git config user.name "GG"
        git config user.email "1563084860@qq.com"
    fi
    # 添加远程仓库（如果不存在）
    if ! git remote -v | grep -q "origin"; then
        git remote add origin "$git_url"
    fi
    # 创建并切换到分支
    if ! git branch | grep -q "$branch_name"; then
        git checkout -b "$branch_name"
    else
        git checkout "$branch_name"
    fi
    # 首次推送需要设置上游
    if ! git branch -r | grep -q "origin/$branch_name"; then
        git push -u origin "$branch_name"
    else
        git push origin "$branch_name"
    fi
    cd - >/dev/null || exit 1
}

# 上传Pod
upload_pod() {
    ensure_in_git_repo "upload"
    
    local git_root=$(get_git_root)
    printf "%b===== 上传Pod =====%b\n" "$BLUE" "$NC"
    
    # 查找podspec
    local podspec_file=$(find "$git_root" -name "*.podspec" | head -n 1)
    if [ -z "$podspec_file" ] || [ ! -f "$podspec_file" ]; then
        printf "%b错误：未找到podspec文件%b\n" "$RED" "$NC"
        exit 1
    fi
    
    # 提取必要信息
    local pod_name=$(grep -E 's\.name[[:space:]]*=[[:space:]]*["'\''].*["'\'']' "$podspec_file" | sed -E 's/.*s\.name[[:space:]]*=[[:space:]]*["'\''](.*)["'\''].*/\1/' | head -n 1)
    local version=$(grep -E 's\.version[[:space:]]*=[[:space:]]*["'\''].*["'\'']' "$podspec_file" | sed -E 's/.*s\.version[[:space:]]*=[[:space:]]*["'\''](.*)["'\''].*/\1/' | head -n 1)
    
    if [ -z "$pod_name" ] || [ -z "$version" ]; then
        printf "%b错误：无法从podspec提取必要信息%b\n" "$RED" "$NC"
        exit 1
    fi
    
    # 验证版本号
    version=$(validate_and_clean_version "$version")
    if [ -z "$version" ]; then
        exit 1
    fi
    
    # 获取当前分支，不进行切换
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    printf "%b当前工作分支: %s%b\n" "$BLUE" "$current_branch" "$NC"
    
    # 判断是否是新仓库，提前给出提示
    local commit_count=$(git rev-list --count HEAD)
    if [ $commit_count -lt 2 ]; then
        printf "%b检测到这可能是新仓库（提交记录较少）%b\n" "$YELLOW" "$NC"
        printf "%b新仓库常因远程默认文件（如README）导致冲突，脚本会自动处理%b\n" "$YELLOW" "$NC"
    fi
    
    # 选择上传模式
    printf "\n%b【代码提交】%b\n" "$BLUE" "$NC"
    printf "1. 自动提交并推送\n"
    printf "2. 手动处理（完成后请按回车）\n"
    read -p "请选择 [1/2，默认: 1]: " upload_mode
    upload_mode=${upload_mode:-1}
    
    if [ "$upload_mode" -eq 1 ]; then
        # 自动模式，使用当前分支
        git add .
        if ! git diff --cached --quiet; then
            git commit -m "Update to version $version"
        fi
        
        # 推送代码（使用当前分支）
        push_with_pull "origin" "$current_branch" || exit 1
        
        # 处理标签 - 增强版
        printf "\n%b【标签管理】%b\n" "$BLUE" "$NC"
        if git tag "$version" 2>/dev/null; then
            printf "%b创建标签 %s 成功%b\n" "$GREEN" "$version" "$NC"
        else
            printf "%b标签 %s 已存在%b\n" "$YELLOW" "$version" "$NC"
        fi
        
        # 推送标签并检查结果
        if git push origin "$version"; then
            printf "%b推送标签 %s 成功%b\n" "$GREEN" "$version" "$NC"
        else
            printf "%b推送标签 %s 失败%b\n" "$RED" "$version" "$NC"
            # 继续执行但标记为警告
        fi
        
        # 验证tag是否存在于远程仓库
        printf "%b验证标签是否推送到远程仓库...%b\n" "$BLUE" "$NC"
        if git ls-remote --tags origin | grep -q "$version"; then
            printf "%b标签 %s 已成功推送到远程仓库%b\n" "$GREEN" "$version" "$NC"
        else
            printf "%b警告：标签 %s 可能未推送到远程仓库%b\n" "$YELLOW" "$version" "$NC"
            # 继续执行但标记为警告
        fi
    else
        # 手动模式，针对新仓库给出特殊提示
        if [ $commit_count -lt 2 ]; then
            printf "%b提示：对于新仓库，推荐使用此命令推送：%b\n" "$BLUE" "$NC"
            printf "%bgit push -u origin %s%b\n" "$GREEN" "$current_branch" "$NC"
        fi
        read -p "请确保已完成提交和推送，按回车继续..." -r
    fi
    
    # 验证并上传
    printf "\n%b【验证并上传】%b\n" "$BLUE" "$NC"
    
    # 先更新CocoaPods仓库，解决CDN错误
    update_cocoapods_repo
    
    # 私有库检查
    read -p "这是公共库吗？(y/n，默认: y): " is_public
    is_public=${is_public:-y}
    
    # 验证podspec
    if ! pod spec lint "$podspec_file" --allow-warnings; then
        printf "%bpodspec验证失败%b\n" "$RED" "$NC"
        exit 1
    fi
    
    # 上传并捕获输出和错误
    local upload_success=0
    local upload_output
    if [ "$is_public" != "y" ]; then
        read -p "请输入私有Spec仓库名称: " spec_repo_name
        upload_output=$(pod repo push "$spec_repo_name" "$podspec_file" --allow-warnings 2>&1)
        upload_success=$?
    else
        upload_output=$(pod trunk push "$podspec_file" --allow-warnings 2>&1)
        upload_success=$?
    fi
    
    # 显示上传命令的输出结果
    printf "%b\n上传过程输出:\n%s%b\n" "$YELLOW" "$upload_output" "$NC"
    
    # 增强的成功判断逻辑
    local final_result=0
    if [ $upload_success -eq 0 ]; then
        # 命令执行成功
        final_result=1
    else
        # 命令执行失败，但检查是否是超时错误且实际可能已成功
        if echo "$upload_output" | grep -qE "Net::OpenTimeout|timeout"; then
            printf "%b检测到网络超时错误，可能是上传成功但确认步骤失败%b\n" "$YELLOW" "$NC"
            
            # 对于公有库，尝试通过trunk验证
            if [ "$is_public" != "y" ]; then
                if verify_pod_upload "$pod_name" "$version"; then
                    printf "%b验证成功：Pod已实际上传%b\n" "$GREEN" "$NC"
                    final_result=1
                else
                    printf "%b验证失败，但可能是缓存问题%b\n" "$YELLOW" "$NC"
                    final_result=0
                fi
            else
                # 私有库提示用户手动检查
                printf "%b私有库可能已上传成功，请手动检查%b\n" "$YELLOW" "$NC"
                final_result=0  # 私有库无法自动验证，仍标记为需要检查
            fi
        else
            # 其他错误
            final_result=0
        fi
    fi
    
    # 输出最终结果
    if [ $final_result -eq 1 ]; then
        printf "\n%b===== 上传成功 =====%b\n" "$GREEN" "$NC"
        printf "%bPod %s v%s 已成功上传%b\n" "$GREEN" "$pod_name" "$version" "$NC"
        printf "%b您可以收到确认邮件作为最终成功凭证%b\n" "$BLUE" "$NC"
    else
        printf "\n%b===== 上传过程出现问题 =====%b\n" "$RED" "$NC"
        printf "%b请检查以上错误信息%b\n" "$YELLOW" "$NC"
        
        # 提供手动验证命令
        if [ "$is_public" != "y" ]; then
            printf "%b手动验证命令: pod repo info %s %s%b\n" "$BLUE" "$spec_repo_name" "$pod_name" "$NC"
        else
            printf "%b手动验证命令: pod trunk info %s%b\n" "$BLUE" "$pod_name" "$NC"
        fi
        
        # 提供手动上传命令
        if [ "$is_public" = "y" ]; then
            printf "%b手动上传命令: pod trunk push %s --allow-warnings%b\n" "$BLUE" "$podspec_file" "$NC"
        else
            printf "%b手动上传命令: pod repo push %s %s --allow-warnings%b\n" "$BLUE" "$spec_repo_name" "$podspec_file" "$NC"
        fi
        exit 1
    fi
}

# 带拉取的推送函数
push_with_pull() {
    local remote="$1"
    local branch="$2"
    printf "%b推送代码到 %s/%s%b\n" "$BLUE" "$remote" "$branch" "$NC"
    
    # 先拉取最新代码
    if ! git pull "$remote" "$branch"; then
        printf "%b拉取代码失败，尝试强制拉取%b\n" "$YELLOW" "$NC"
        if ! git pull "$remote" "$branch" --rebase; then
            printf "%b强制拉取失败，请手动解决冲突%b\n" "$RED" "$NC"
            return 1
        fi
    fi
    
    # 推送代码
    if ! git push "$remote" "$branch"; then
        printf "%b推送代码失败%b\n" "$RED" "$NC"
        return 1
    fi
    
    return 0
}

# 主函数
main() {
    check_dependencies
    
    if [ $# -eq 0 ]; then
        printf "%b===== PodGG 工具 =====%b\n" "$BLUE" "$NC"
        printf "用法: podgg <命令> [参数]\n"
        printf "命令:\n"
        printf "  upload   - 上传Pod到CocoaPods\n"
        printf "  help     - 显示帮助信息\n"
        printf "  test     - 测试模式\n"
        exit 0
    fi
    
    local command="$1"
    case "$command" in
        upload)
            upload_pod
            ;;
        help)
            printf "%b===== PodGG 工具帮助 =====%b\n" "$BLUE" "$NC"
            printf "upload - 上传Pod到CocoaPods\n"
            printf "help   - 显示帮助信息\n"
            printf "test   - 测试模式\n"
            ;;
        test)
            TEST_MODE=1
            upload_pod
            ;;
        *)
            printf "%b错误：未知命令 '%s'%b\n" "$RED" "$command" "$NC"
            printf "使用 'podgg help' 查看可用命令%b\n" "$YELLOW" "$NC"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
