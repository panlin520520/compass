# App 静态资源外置目录

Flutter 的 assets 目录内容放在此处，不会打进 Spring Boot jar，jar 只保留业务代码。

## 目录结构

与 flutter_application_1/assets 内容一致，例如：

    app-assets/
      logo.png
      kefu.jpg
      gold/
      luban/
      default-tip-json/

前端访问 URL 不变，例如：

    http://服务器:8066/app-assets/gold/0-SimplePlate.png

## 首次使用：同步资源

在 compass-server 目录下执行：

    scripts\sync-app-assets.bat

或 PowerShell：

    .\scripts\sync-app-assets.ps1

## 配置说明

application.yml 已配置 ruoyi.app-assets-path，可用环境变量 APP_ASSETS_PATH 覆盖。

未配置时，启动会自动探测 app-assets 目录；本地开发还可自动使用 flutter_application_1/assets。

生产环境建议在 application.yml 中写绝对路径，例如：

    ruoyi.app-assets-path: D:/ruoyi/app-assets

或使用环境变量：

    set APP_ASSETS_PATH=D:\ruoyi\app-assets
    java -jar compass.jar

## 部署步骤

1. mvn package 打 jar（已排除 resources/assets，jar 体积更小）
2. 将 compass.jar 与 app-assets 文件夹一起上传到服务器
3. 配置 APP_ASSETS_PATH 或 ruoyi.app-assets-path
4. 启动后日志应出现：App 静态资源外置目录
5. 浏览器访问 http://IP:8066/app-assets/logo.png 验证

## 图片压缩（加快加载）

资源体积较大时，可在 `compass-server` 目录执行：

    scripts\compress-app-assets.bat

或 PowerShell：

    .\scripts\compress-app-assets.ps1

脚本会**原地**压缩 PNG/JPG（256 色调色板 + 最高 PNG 压缩；JPEG quality 85），通常可减少约 70% 体积，罗盘盘面清晰度可接受。压缩后请用真机查看盘面与透明底图是否正常。

若之后从 `flutter_application_1/assets` 再次执行 `sync-app-assets`，会覆盖压缩结果，需重新压缩，或先将压缩后的 `app-assets` 拷回 Flutter 工程作为图源。

## 开发注意

- 未同步时，本地开发会自动使用 flutter_application_1/assets
- 上线前务必执行同步脚本，服务器只部署 app-assets
- 修改 Flutter 图片后，上线需重新同步 app-assets，并视情况再执行压缩脚本
- app-assets 大文件已加入 .gitignore，勿提交到 git
