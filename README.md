# SGimmicks VPM Repository

SGimmicksとCastTimerを、VRChat Creator Companionから追加・更新できるVPMリポジトリとして配布するためのプロジェクトです。

## GitHub Pages公開

1. `Build-VpmRepository.ps1` をGitHubユーザー名付きで実行します。
2. このフォルダーをGitHubの公開リポジトリへpushします。
3. GitHubの `Settings > Pages` で `Deploy from a branch`、ブランチ `main`、フォルダー `/docs` を選びます。
4. 公開された `https://<ユーザー名>.github.io/<リポジトリ名>/index.json` をVCCへ登録します。

```powershell
.\Build-VpmRepository.ps1 -Version 2.1.3 -GitHubOwner <ユーザー名> -RepositoryName SGimmicks-VPM
```

## 次回以降の更新

SGimmicksPackageProjectを更新し、Semantic Versioningに従ってバージョンを上げて再実行します。`docs/index.json` は過去バージョンを残したまま新しいバージョンを追加します。
