# CloudFrontIPSelector

CloudFrontIPSelector是一个用来选择连接延迟最低的CloudFront IP的工具。

## 背景

由于AWS的DNS功能非常优秀，AWS CloudFront的用户通常能够享受到非常稳定的体验。但是，多数情况下DNS可能会返回一些不太理想的IP，导致连接速度变慢或不稳定。

因此，一些中国用户倾向于绑定Host去优化访问CloudFront的体验。我创建这个脚本的目的是去选择一个低延迟的IP以便于中国用户绑定IP。

## 致谢

本项目基于 [BruceWind/CloudFrontIPSelector](https://github.com/BruceWind/CloudFrontIPSelector) 开发，感谢原作者的无私分享。本版本在原项目基础上增加了Docker支持和一键部署功能，使其更易于在OpenWrt环境中使用。

## 一键安装

# 方式1：直接运行（推荐）
```bash
curl -sSL https://raw.githubusercontent.com/rdone4425/CloudFrontIPSelector/main/1.sh | bash
```

## 使用说明

1. 环境要求
   - OpenWrt系统
   - 稳定的网络连接
   - 足够的存储空间（约50MB）

2. 网络环境
   建议您使用**网线**连接您的路由器，或确保您的网络连接稳定。如果没有稳定的连接，此脚本可能无法获取任何低延迟IP。
   
   判断网络稳定性的方法：
   - ping您的网关IP（如192.168.0.1）1分钟
   - 确保ping值稳定，无丢包

3. 运行程序
   安装完成后，会显示交互式菜单：
   ```
   === CloudFront IP选择器 ===
   1. 启动服务
   2. 停止服务
   3. 查看日志
   4. 查看结果
   5. 重启服务
   6. 更新程序
   0. 退出
   ```

4. 查看结果
   - 结果保存在：`~/cloudfront-docker/data/result.txt`
   - 日志文件在：`~/cloudfront-docker/data/cloudfront.log`

## 配置说明

可以通过修改 `~/cloudfront-docker/docker-compose.yml` 文件调整以下参数：

- THRESHOLD：延迟阈值（默认150ms）
- PING_COUNT：Ping测试次数（默认5次）

如果获取不到任何IP，可以适当调高THRESHOLD值。

## 功能特点

- 自动安装所需环境（Docker等）
- 自动测试CloudFront节点延迟
- 排除中国IP地址
- 优先测试亚洲地区IP
- 支持自动更新
- 交互式管理界面

## 其他说明

1. 为什么不测试带宽？
   通过测试发现，CloudFront的IP下载速度普遍都能跑满200M带宽，所以主要关注延迟即可。

2. 想尝试Gcore-CDN？
   可以参考：https://github.com/BruceWind/GcoreCDNIPSelector

### 声明
- 本项目用于修复网络体验问题，请遵守当地法律，请勿用于爬🪜。
- 本程序不会定期更新CloudFront IP，所以如果你发现连接质量下降，你可以重新运行本程序来获取最新的IP。

## 更新日志

### v1.0.0
- 初始版本发布
- 支持Docker容器化部署
- 支持自动安装依赖
- 支持交互式管理
- 支持自动更新
