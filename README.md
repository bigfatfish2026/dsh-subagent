# dsh-subagent（源码自建版）

`@deepseek-ai/dsh-subagent` 0.2.1-rc.5 的**上游源码自建**，加一个结算通知开关。源码取自官方 monorepo 对应 tag，`lib/` 由本仓库自己构建。

上游仓库：[deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) `packages/subagent/subagent`，tag `dsh-v0.2.1-rc.5`（commit `b830ec950faba0a46dda564be3e2d854afed94f1`），MIT 许可，署名保留在 `LICENSE`、`README.upstream.md`（英文）与 `README.upstream.zh.md`（中文）。

## 改了什么

只有一处行为变更：**子会话结束时是否把子级最后一条回复投给父会话**。

- `src/index.ts:192` 的 `Config` 接口、`src/index.ts:200` 的 `SubagentRuntime.Config` schema 新增 `settlementNotice: z.boolean().default(true)`。**不**加 `volatile`——纯行为开关，不触发运行时重建。
- `src/manager.ts:1190` 的 `SubagentManager.notifySettlement()` 开头加守卫：开关为 `false` 时直接返回。
- `src/manager.ts:161` 的 `SubagentManager` 构造多收一个 `settlementNotice` 访问器，和现有 `maxActiveSubagents` 一样由服务层从 `this.config` 闭包传入（这个类里没有 `this.config`，config 归服务类所有）。

默认 `true`，行为和上游完全一致。设成 `false` 后：子会话结束不再向父会话注入 `settlementSummary` 消息，父会话不会被这条投递唤醒；生命周期、结果 resolve、归档、`send_message` 回传都不受影响。`delivery: 'caller'` 的子会话走工具返回值回传，不进 `notifySettlement`，因此与这个开关无关。

## 目录

- `src/`、`tests/`、`locale/`、`README.upstream.md`、`README.upstream.zh.md`、`README.i18n.yaml`：上游 rc.5 原样。
- `lib/`：构建产物，随仓库提交。宿主用 `link:` 直接读这个目录，不会替你跑构建。
- `typert/`：`lib/typert.host.*` 与 `lib/typert.remote-client.*` 的预生成源，构建时拷进 `lib/`。
- `tsconfig.json`：从上游根 `tsconfig.base.json` 裁剪内联；`tsconfig.upstream.json` 保留原版备查。
- `tsdown.config.ts`、`scripts/build.sh`：构建配置与入口脚本。
- `package.json`：上游的 `workspace:*` / `workspace:~` 已换成确切版本。

## 构建

```bash
npm run build          # = bash scripts/build.sh
```

脚本会做四件事：装构建工具到 `.build-tools/`（gitignored，默认 `typescript@^6.0.3`、`tsdown@^0.22.2`）→ `tsc -p tsconfig.json` 出 `lib/types/` → `tsdown` 以 `lib/types/index.js` 为入口 bundle 出 `lib/index.js` → 把 `typert/` 下四个文件拷进 `lib/` 并逐个 `node --check`。

两个坑记在这：

- **`tsdown` 的入口必须是 `lib/types/index.js` 而不是 `src/index.ts`。** `.ts` 直接进 rolldown 时 `@Remote()` 装饰器不会按 legacy 语义转换，产出的 JS 语法都过不了 `node --check`。官方根配置也走编译后 JS 入口。
- **`tsc` 带 `--noCheck`。** 本包的类型图会牵到几乎整个 `@deepseek-ai` 宿主包树，在这块 Pi 的堆上做全量检查会 OOM。emit 不受影响——产物 JS/`d.ts` 与 npm 发布的 rc.5 逐字节核对过，只差文件尾那行指向不存在 `.map` 的 `sourceMappingURL` 注释（上游发布包里同样没有 `.map`）。

`tsc` 开了 `rewriteRelativeImportExtensions`，源码里 `./types.ts` 这种后缀会被重写成 `.js`；`d.ts` 里保留 `.ts`，上游发布产物也是这样，`moduleResolution: bundler` 能解析。

## 两个非自建产物

`typert/` 下那四个文件是 `@deepseek-ai/dsh-typert-generator` 从 FaceModel 生成的，不含业务逻辑，只描述 remote 方法的参数 schema。自己生成要跑整个 monorepo 的 generator，这里沿用 rc.5 官方发布的那份预生成产物。只有上游改了 remote 表面才需要跟着换。

## 怎么用

在 profile 里用 `link:` 覆盖，让宿主解析到这个目录而不是 npm 上的包：

```json
{
  "dependencies": {
    "@deepseek-ai/dsh-subagent": "link:/home/julia/dev/dsh-subagent"
  }
}
```

改完 `pnpm i`，重启宿主生效。关掉结算通知：

```json
{
  "plugins": {
    "@deepseek-ai/dsh-subagent": {
      "settlementNotice": false
    }
  }
}
```

## 注意

- `tests/` 是上游原样，跑不起来：依赖 monorepo 内部 fixture（`../../../core/agent-loop/tests/mock-adapter.ts` 之类）和未发布的兄弟包。本仓库只负责构建。
- 这是源码 fork，不是产物补丁。早先那套「从全局安装目录拷 `lib/` 再打 patch」的 `patches/` 和 `scripts/rebuild.sh` 已随改造删除，历史留在 git log 里。
- 不要往这个仓库里塞 `node_modules` 和 `.build-tools`。
