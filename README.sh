# podgg

一个简化CocoaPods库创建与管理的命令行工具，专为iOS开发者设计，简化Pod库的创建、版本管理和上传流程。

## 介绍

`podgg` 是一个实用的命令行工具，旨在简化iOS/macOS开发者使用CocoaPods的工作流程。它提供了直观的命令集，帮助你快速创建Pod库、管理版本并上传到CocoaPods仓库，减少重复操作和配置工作。

主要功能：
- 一键创建符合规范的Pod库结构
- 简化版本管理和Git配置
- 智能处理上传过程中的常见问题（如CDN错误、网络超时）

## 安装

使用以下命令一键安装：curl -fsSL https://gitee.com/6022463/PodGG/raw/master/install.sh | bash
## 使用方法

### 创建新Pod库podgg create按照提示输入Pod名称和仓库地址，工具会自动创建完整的Pod库结构、配置Git并自动进入项目目录。

### 上传Pod库podgg upload在Pod库目录（或其父目录）执行，工具会自动检测项目、验证配置并上传到CocoaPods仓库。

### 查看帮助podgg help显示所有可用命令和使用说明。

### 安装为系统命令podgg install将工具安装为系统全局命令（通常无需手动执行，安装脚本会自动处理）。

### 卸载podgg uninstall从系统中移除工具。

## 更新

如需更新到最新版本，只需重新执行安装命令即可：curl -fsSL https://gitee.com/6022463/PodGG/raw/master/install.sh | bash
