# dsh-subagent（源码自建版）维护须知

这份文件写给下次 dsh 升版本的人。仓库是什么、怎么构建见 `README.md`，这里只讲**跟进升级的步骤**和**已经踩过的坑**。

## 这个仓库是什么

官方 `@deepseek-ai/dsh-subagent` 0.2.1-rc.5 的源码自建版。源码取自官方 monorepo 的 tag `dsh-v0.2.1-rc.5`（commit `b830ec9`）里的 `packages/subagent/subagent`，`lib/` 由本仓库自己构建并随仓库提交。

唯一的功能改动是 `settlementNotice` 开关，默认 `true`，行为与上游一致：

- `src/index.ts`：`SubagentRuntime.Config` 接口加 `settlementNotice: boolean`，schema 加 `z.boolean().default(true)`；创建 `SubagentManager` 时把 `() => this.config.settlementNotice` 当访问器传进去（这个类里没有 `this.config`）。
- `src/manager.ts`：`SubagentManager` 构造函数收这个访问器，`notifySettlement()` 开头 `=== false` 直接返回。

除此之外 `src/`、`tests/`、`locale/`、`README.upstream.md`、`README.upstream.zh.md`、`tsconfig.upstream.json` 与 tag 原样一致，可以用 diff 核对。

## 升级流程

按顺序做完，别跳步。先把新版本号定下来，下面命令都用 `$VERSION`：

```bash
VERSION=0.2.1-rc.5   # 换成新版本
```

**1. 取新 tag 的源码。不要 clone 整仓**——350MB 在这块 Pi 上会卡死。用 codeload 的 tag tarball（34MB 左右），只解那一个包目录：

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

**5. 覆盖源码、按第 4 步结论重打补丁。** `src/`、`tests/`、`locale/`、`README.upstream.md`、`README.upstream.zh.md`、`tsconfig.upstream.json` 从 `/tmp/dsh-src/` 拷过来；`README.md` 是本仓自己的，别覆盖。`tsconfig.json` 是本仓从上游 `tsconfig.base.json` 裁剪内联的，新版根配置有变化就跟着调。

**6. 重编、核对、提交。** 构建见下一节，核对走「验收清单」，然后更新 `package-lock.json`、提交推送。

## 构建

```bash
npm run build          # = bash scripts/build.sh
```

脚本做四件事：装构建工具到 `.build-tools/`（gitignored）→ `tsc -p tsconfig.json` 出 `lib/types/` → `tsdown --config tsdown.config.ts` 以 `lib/types/index.js` 为入口 bundle 出 `lib/index.js` → 把 `typert/` 四个文件拷进 `lib/` 并逐个 `node --check`。

两个必须保留的细节：

- **`tsc` 带 `--noCheck`。** 本包类型图牵到几乎整个 `@deepseek-ai` 宿主包树，4GB 堆上做全量检查会 OOM；只关检查，emit 不受影响（产物与官方 npm 包对过，除补丁文件外只差文件尾那行指向不存在 `.map` 的 `sourceMappingURL`）。
- **`tsdown` 入口是 `lib/types/index.js`，不是 `src/index.ts`。** `.ts` 直接进 rolldown 时 `@Remote()` 装饰器不按 legacy 语义转换，产物语法过不了 `node --check`。

产物结构必须匹配 `package.json` 的 `exports` / `files`：

- `.` → `lib/index.js` + `lib/types/index.d.ts`
- `./internal` → `lib/types/internal.js` + `.d.ts`
- `./client` → `lib/types/client.js` + `.d.ts`
- `./typert` → `lib/typert.host.js` + `.d.ts`
- `./remote` → `lib/typert.remote-client.js` + `.d.ts`

少一个，宿主那边 import 就炸。`exports` 里另有 `./src/*`、`./package.json`、`./locale/*.json`，直接指向源码与语言包，不涉及构建产物。

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

## 测试跑不全

`tests/` 是上游原样。24 个 spec 里有 12 个从 `../../../core/agent-loop/tests/mock-adapter.ts`、`../../../settings/settings/tests/live-config.ts`、`../../../llm/llm-deepseek/tests/helpers.ts` 这类 monorepo 内部路径 import fixture（还有未发布的兄弟包），公开环境加载就失败。**这不是回归，别去修，也别把路径改成 npm 包。**

能跑的那半用 vitest 跑，仓库没带测试运行器，现装：

```bash
grep -L "from '\.\./\.\./\.\./" tests/*.spec.ts      # 能跑的清单
npx -y vitest@3 run $(grep -L "from '\.\./\.\./\.\./" tests/*.spec.ts)
```

全挂也别慌，先看构建与冒烟结论；能跑的那部分必须绿。

## 验收清单

- [ ] `lib/index.js` 导出数（rc.5 是 25 个）：

```bash
node --input-type=module -e "const m=await import('./lib/index.js'); console.log(Object.keys(m).length)"
```

- [ ] 五个 exports 子路径都能 import（数量可以不等于入口的）：

```bash
node --input-type=module -e "
for (const s of ['', '/client', '/internal', '/typert', '/remote']) {
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

- [ ] `lib` 里 js 文件数（rc.5 是 25 = 22 个 `lib/types/*.js` + `lib/index.js` + 两个 typert.js），d.ts 是 24：

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

这个包在 profile 里是 `link:` 进宿主的那份，宿主直接读 `lib/`，不会替你跑构建。**改完要重启宿主才生效，重启权在主会话，别自己动手重启。**
