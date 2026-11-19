# dsh-subagent（源码自建版）维护须知

这份文件写给下次 dsh 升版本的人。仓库是什么、怎么构建见 `README.md`，这里只讲**跟进升级的步骤**和**已经踩过的坑**。

## 这个仓库是什么

官方 `@deepseek-ai/dsh-subagent` 0.2.2-rc.5 的源码自建版。源码取自官方 monorepo 的 tag `dsh-v0.2.2-rc.5`（commit `9c2670d`）里的 `packages/subagent/subagent`，`lib/` 由本仓库自己构建并随仓库提交。

唯一的功能改动是 `settlementNotice` 开关，默认 `true`，行为与上游一致：

- `src/index.ts`：`SubagentRuntime.Config` 接口加 `settlementNotice: boolean`，schema 加 `z.boolean().default(true)`；创建 `SubagentManager` 时把 `() => this.config.settlementNotice` 当访问器传进去（这个类里没有 `this.config`）。
- `src/manager.ts`：`SubagentManager` 构造函数收这个访问器，`notifySettlement()` 开头 `=== false` 直接返回。

除此之外 `src/`、`locale/`、`README.upstream.md`、`README.upstream.zh.md`、`tsconfig.upstream.json` 与 tag 原样一致，可以用 diff 核对。`tests/` 例外：上游 33 个 spec 里 14 个依赖 monorepo 内部 fixture，在本仓永远跑不了，已裁掉，只留 12 个（其中 `external-activation.spec.ts` 有 4 条在单包环境仍失败，见下面「测试」一节）。

## 升级流程

按顺序做完，别跳步。先把新版本号定下来，下面命令都用 `$VERSION`：

```bash
VERSION=0.2.2-rc.5   # 换成新版本
```

**1. 取新 tag 的源码。不要 clone 整仓**——350MB 在本机上会卡死。用 codeload 的 tag tarball（34MB 左右），只解那一个包目录：

```bash
rm -rf /tmp/dsh-src /tmp/dsh-src.tgz && mkdir -p /tmp/dsh-src
curl -fL -o /tmp/dsh-src.tgz \
  "https://codeload.github.com/deepseek-ai/deepseek-harness/tar.gz/refs/tags/dsh-v$VERSION"
tar xzf /tmp/dsh-src.tgz -C /tmp/dsh-src --strip-components=4 \
  --wildcards '*/packages/subagent/subagent/*'
ls /tmp/dsh-src    # src/ tests/ locale/ package.json tsconfig.json ...
```

`--strip-components=4` 去掉 `deepseek-harness-dsh-v<版本>/packages/subagent/subagent` 这四层；通配符只落地这个包目录，别的文件不进磁盘。

**2. 拉官方 npm 产物当参照。** typert 那四份只有 npm 产物里有，tag 源码里没有：

```bash
rm -rf /tmp/dsh-npm && mkdir -p /tmp/dsh-npm && cd /tmp/dsh-npm
npm pack "@deepseek-ai/dsh-subagent@$VERSION"
tar xzf "deepseek-ai-dsh-subagent-$VERSION.tgz" --strip-components=1
ls /tmp/dsh-npm/lib   # index.js types/ typert.host.* typert.remote-client.*
```

**3. 对照新 `package.json` 改本仓。** 上游的 `workspace:*` / `workspace:~` 全部换成确切版本（`dependencies`、`peerDependencies`、`devDependencies` 三处）；`exports`、`files`、`main`、`types` 跟新版对齐；`version` 跟着改。`scripts` 里 `build` / `typecheck` 是本仓自己的，保留。

**4. 检查上游是否已经自带 `settlementNotice`：**

```bash
grep -rn settlementNotice /tmp/dsh-src/src
```

有输出就是上游自己实现了——把我们的补丁删掉（`src/index.ts` 的字段与传参、`src/manager.ts` 的构造参数与守卫），`src/` 换回上游原样再构建。别留两套。

**5. 覆盖源码、按第 4 步结论重打补丁。** `src/`、`tests/`、`locale/`、`README.upstream.md`、`README.upstream.zh.md`、`tsconfig.upstream.json` 从 `/tmp/dsh-src/` 拷过来（拷完按下面「测试」一节裁掉跑不了的 spec）；`README.md` 是本仓自己的，别覆盖。`tsconfig.json` 是本仓从上游 `tsconfig.base.json` 裁剪内联的，新版根配置有变化就跟着调。

**6. 重编、核对、提交。** 构建见下一节，核对走「验收清单」，然后更新 `package-lock.json`、提交推送。

## 构建

```bash
npm run build          # = bash scripts/build.sh
```

脚本做四件事：装构建工具到 `.build-tools/`（gitignored）→ `tsc -p tsconfig.json` 出 `lib/types/` → `tsdown --config tsdown.config.ts` 以 `lib/types/index.js` 为入口 bundle 出 `lib/index.js` → 把 `typert/` 四个文件拷进 `lib/` 并逐个 `node --check`。

两个必须保留的细节：

- **`tsc` 带 `--noCheck`。** 本包类型图牵到几乎整个 `@deepseek-ai` 宿主包树，默认堆（约 4GB）上做全量检查会 OOM；只关检查，emit 不受影响（产物与官方 npm 包对过，除补丁文件外只差文件尾那行指向不存在 `.map` 的 `sourceMappingURL`）。
- **`@types/node` 装在 `.build-tools` 里，`tsc` 得带 `--typeRoots`。** `tsconfig.json` 的 `types: ["node"]` 只会从项目向上的 `node_modules/@types` 找，`.build-tools` 不在那条链上；`build.sh` 把 `@types/node` 跟 typescript/tsdown 一起装进去，并显式传 `--typeRoots "$BUILD_TOOLS/node_modules/@types"`，否则报 TS2688。
- **`typecheck` 要给够堆。** `npm run typecheck` 直接跑会 `tsc: not found`（typescript 装在 `.build-tools`），走 `.build-tools/node_modules/.bin/tsc`；全量检查在 `NODE_OPTIONS=--max-old-space-size=6144` 下 4s 跑完、零错误（默认 4GB 堆才会 OOM）：
  `NODE_OPTIONS=--max-old-space-size=6144 .build-tools/node_modules/.bin/tsc -p tsconfig.json --noEmit --typeRoots .build-tools/node_modules/@types`
- **`tsdown` 入口是 `lib/types/index.js`，不是 `src/index.ts`。** `.ts` 直接进 rolldown 时 `@Remote()` 装饰器不按 legacy 语义转换，产物语法过不了 `node --check`。

产物结构必须匹配 `package.json` 的 `exports` / `files`：

- `.` → `lib/index.js` + `lib/types/index.d.ts`
- `./client` → `lib/types/client.js` + `.d.ts`
- `./typert` → `lib/typert.host.js` + `.d.ts`
- `./remote` → `lib/typert.remote-client.js` + `.d.ts`

少一个，宿主那边 import 就炸。`exports` 里另有 `./src/*`、`./package.json`、`./locale/*.json`，直接指向源码与语言包，不涉及构建产物。

**rc.5 起上游删掉了 `src/internal.ts` 与 `./internal` 子路径**（rc.1 有），宿主的 `dsh-tool-subagent-control` 也改成只 import 主入口了；升级时别把 `./internal` 加回来。

## typert 四份什么时候要重出

`lib/typert.host.js`、`lib/typert.host.d.ts`、`lib/typert.remote-client.js`、`lib/typert.remote-client.d.ts` 由 `@deepseek-ai/dsh-typert-generator` 构建期从 TS 类型生成，`typert/` 里存的是预生成源，`build.sh` 拷进 `lib/`。**`typert.host.js` 会被宿主 typert-loader 加载并严格校验，形状不对当场大声报错**，不会静默降级。

- 只有「插件自身的 `@Remote` 方法签名变了」或者「typert 协议形状变了」才必须重出这四份；其余情况沿用官方发布的那份就够了。
- generator 要整个 monorepo 的 tsconfig 与源码树，单包仓库跑不了。所以默认策略是拿官方 npm 产物里的同四份，升级时核对是否一致：

```bash
for f in typert.host.js typert.host.d.ts typert.remote-client.js typert.remote-client.d.ts; do
  cmp -s "/tmp/dsh-npm/lib/$f" "typert/$f" && echo "same $f" || echo "DIFF $f"
done
```

有 `DIFF` 就说明上游重出过，把官方那四份拷进 `typert/` 再重跑构建。

## 测试

`tests/` 现有 12 个 spec，196 条用例里 192 条过、4 条败；上游那 14 个依赖 monorepo 内部 fixture 的已在本仓裁掉，`git log` 里查得到。败的 4 条全在 `external-activation.spec.ts`（`delivers the full failed result with parent delivery`、`preserves the completed result for parent delivery when cleanup fails`、`reports external completed/aborted without offering another turn`），现象是 parent inbox `nextTurn` 空、通知没落地；用未打补丁的上游 rc.5 源码同样 4 条败，与本仓 `settlementNotice` 补丁无关，是单包测试环境里 `ctx.agents.get(parentId)` 拿到的 Agent 与 fixture 注册的不是同一个投递对象。要么按同样口径再裁，要么另开票查，别拿它当「补丁坏了」。裁掉的判据就是一条：任何 `from '../../../...'` 的 import 都指向上游 monorepo 里不存在的路径（`core/agent-loop/tests/mock-adapter.ts`、`settings/settings/tests/live-config.ts`、`llm/llm-deepseek/tests/helpers.ts`、`session/session-persistence-jsonl/src/format.ts`、`storage/*`、`schedule/*`），公开环境加载即失败。**这不是回归，别去修，也别把路径改成 npm 包。**

跑之前先装依赖。`package-lock.json` 现在是完整的，直接照 lock 装就行（rc.1 那会儿 lock 里没有 testkit，才要 `--no-save` 单独补）：

```bash
rm -rf node_modules && npm ci      # 99 个包，约 3s（有缓存）
npx -y vitest@3 run                # 12 files / 196 tests，192 过 4 败（见上）
```

**别在 `node_modules/` 里留着上一版的包再跑 `npm install`**：npm 会拿旧的 rc.x 树去解 peer，报 ERESOLVE 说 `dsh-agent@rc.1` 与 root 要的 rc.5 冲突。要么先 `rm -rf node_modules`，要么 `mv node_modules /tmp/x` 之后 `npm install --package-lock-only` 重解 lock。

升级取新 tag 源码后，`tests/` 会重新带回来那 14 个。判据：`grep -l "from '\.\./\.\./\.\./" tests/*.spec.ts` 列出的就是，连它们专属的 helper/fixture 一起删；删之前确认没有别的 spec 引用（`grep -rn <名字> tests/src`）。

## 验收清单

- [ ] `lib/index.js` 导出数（0.2.2-rc.4 及以前是 25 个，rc.5 是 26 个）：

```bash
node --input-type=module -e "const m=await import('./lib/index.js'); console.log(Object.keys(m).length)"
```

- [ ] 四个 exports 子路径都能 import（数量可以不等于入口的；rc.5 没有 `/internal`）：

```bash
node --input-type=module -e "
for (const s of ['', '/client', '/typert', '/remote']) {
  const m = await import('@deepseek-ai/dsh-subagent' + s)
  console.log('ok', s || '.', Object.keys(m).length)
}"
```

- [ ] `Config({})` 里 `settlementNotice === true`：

```bash
node --input-type=module -e "
const { SubagentRuntime } = await import('./lib/index.js')
console.log(SubagentRuntime.Config({}).settlementNotice)"
```

- [ ] `lib` 里 js 文件数（rc.5 仍是 25 = 22 个 `lib/types/*.js` + `lib/index.js` + 两个 typert.js；rc.5 少了 `internal.ts`、多了 `names.ts`，数量没变），d.ts 是 24：

```bash
find lib -name '*.js' | wc -l; find lib -name '*.d.ts' | wc -l
```

- [ ] 与官方产物逐文件 diff，结论只能是「我们的补丁 + 打包器格式差异 + 文件尾 `sourceMappingURL` 注释」：

```bash
diff -rq /tmp/dsh-npm/lib lib
# lib/types 下按行去掉注释后，应只剩 index/manager 两个补丁文件
for f in /tmp/dsh-npm/lib/types/*; do b=$(basename "$f")
  diff -q <(grep -v -E '^\s*//' "$f") <(grep -v -E '^\s*//' "lib/types/$b") >/dev/null || echo "diff: $b"
done
# bundle 去掉注释行后，差异应只剩补丁本身
diff -u <(grep -v -E '^\s*//' /tmp/dsh-npm/lib/index.js) <(grep -v -E '^\s*//' lib/index.js)
```

bundle 里还会看到 `/* @__PURE__ */` 注解和个别 `default: break;` 的有无，这是 tsdown 版本不同带来的打包器格式差异，语义不变，别为此改源码。

- [ ] `package-lock.json` 里 dsh 包的版本全是新版号（`node_modules/` 下链到全局安装树的 `../../.nvm/...` 条目是 link 安装留下的，正常，按前缀过滤即可）：

```bash
node -e "const p=require('./package-lock.json'), v=require('./package.json').version
const bad=Object.entries(p.packages).filter(([k,x])=>k.startsWith('node_modules/@deepseek-ai/dsh-')&&x.version&&x.version!==v)
console.log(bad.length?bad:'ok '+v)"
```

- [ ] 提交换作者 `蓝色大肥鱼 <bigfatfish2026@163.com>`，message 写清版本与改动。

## 生效方式

这个包在 profile 里是 `link:` 进宿主的那份，宿主直接读 `lib/`，不会替你跑构建。**改完要重启宿主才生效，重启由维护者执行，别自己动手。**
