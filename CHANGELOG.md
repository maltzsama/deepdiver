# Changelog

All notable changes to LakeDeepDiver will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.5.0](https://github.com/maltzsama/deepdiver/compare/v0.4.1...v0.5.0) (2026-08-29)


### Features

* **helm:** add native Gateway API support (Gateway + HTTPRoute) ([05680f3](https://github.com/maltzsama/deepdiver/commit/05680f31cb987bd0a9db1a4fad6006932f078a7b))
* **helm:** add native Gateway API support (Gateway + HTTPRoute) ([41380f4](https://github.com/maltzsama/deepdiver/commit/41380f46934d6cc0e895c0cac9c8ecbe5d040bb7))


### Bug Fixes

* **helm:** require at least one gateway listener ([ddfc9e8](https://github.com/maltzsama/deepdiver/commit/ddfc9e83c9a072e31d753064cad5c07097815385))

## [0.4.1](https://github.com/maltzsama/deepdiver/compare/v0.4.0...v0.4.1) (2026-08-29)


### Bug Fixes

* **helm:** document rename and reinstall path for existing installs ([fda7a8f](https://github.com/maltzsama/deepdiver/commit/fda7a8ff676d10acc0e1ef9cff2d0cef47c5b9ad))
* **helm:** document rename and reinstall path for existing installs ([df4de27](https://github.com/maltzsama/deepdiver/commit/df4de27a968b812532af946755aded09fe0816d0))

## [0.4.0](https://github.com/maltzsama/lakedeepdiver/compare/v0.3.5...v0.4.0) (2026-08-29)


### Features

* rename project to DeepDiver ([25cfa0a](https://github.com/maltzsama/lakedeepdiver/commit/25cfa0a1d14693148cb36772d2550d9f30bdbea1))
* rename project to DeepDiver ([5412dd9](https://github.com/maltzsama/lakedeepdiver/commit/5412dd9b108312d7beaa50265c4b21bd73ed8cf2))

## [0.3.5](https://github.com/maltzsama/lakedeepdiver/compare/v0.3.4...v0.3.5) (2026-08-26)


### Bug Fixes

* **helm:** add a real readinessProbe to the Solid Queue workers ([98e1e98](https://github.com/maltzsama/lakedeepdiver/commit/98e1e9840ac6f39c6d6a5628ed9254fe28fc185e))
* **helm:** add a real readinessProbe to the Solid Queue workers ([783edde](https://github.com/maltzsama/lakedeepdiver/commit/783edde1eeb4dfc428d20a5045fabecf35313b3a))

## [0.3.4](https://github.com/maltzsama/lakedeepdiver/compare/v0.3.3...v0.3.4) (2026-08-26)


### Bug Fixes

* **helm:** add schema coverage, web resource defaults, migration Job scheduling hooks ([a4e8b51](https://github.com/maltzsama/lakedeepdiver/commit/a4e8b5190aeec82b6bf5c160d04eff25b6d4de79))
* **helm:** fix install-blocking pod scheduling and probe bugs ([491a875](https://github.com/maltzsama/lakedeepdiver/commit/491a875f0800a7640f543129fbc8a9f37cc89c7f))
* **helm:** fix real install-blocking bugs (round 4) ([a98b67a](https://github.com/maltzsama/lakedeepdiver/commit/a98b67a001aa29d2268fc96e398d0c943f36c9a4))

## [0.3.3](https://github.com/maltzsama/lakedeepdiver/compare/v0.3.2...v0.3.3) (2026-08-26)


### Bug Fixes

* **spec:** expect cache-busted icon URL in auth smoke test ([5ef6a51](https://github.com/maltzsama/lakedeepdiver/commit/5ef6a51fa355333cff67df52f58293a83df90088))
* **spec:** expect cache-busted icon URL in auth smoke test ([56a1d70](https://github.com/maltzsama/lakedeepdiver/commit/56a1d70336c74c8a5c62cd5158e8560848d3c4fc))

## [0.3.2](https://github.com/maltzsama/lakedeepdiver/compare/v0.3.1...v0.3.2) (2026-08-26)


### Bug Fixes

* **icons:** serve updated icon without inversion, bundle chart icon as data URI ([f8fd304](https://github.com/maltzsama/lakedeepdiver/commit/f8fd30424d144faa967b17bac6f78ac89887fb74))
* **icons:** serve updated icon without inversion, bundle chart icon as data URI ([aedf79d](https://github.com/maltzsama/lakedeepdiver/commit/aedf79d6adff9c8104f9f0ffd8f769ca9de7f958))

## [0.3.1](https://github.com/maltzsama/lakedeepdiver/compare/v0.3.0...v0.3.1) (2026-08-25)


### Bug Fixes

* **helm:** add the missing chart icon ([e504fe8](https://github.com/maltzsama/lakedeepdiver/commit/e504fe8a28a44f874a0d7fa6949677e7bb3e7d19))
* **helm:** fix runtime bugs and close extensibility gaps from install review ([7684488](https://github.com/maltzsama/lakedeepdiver/commit/768448806363d054b50b42e081bf15bf489df7b2))
* **helm:** runtime bugs and extensibility gaps from install review ([b801a39](https://github.com/maltzsama/lakedeepdiver/commit/b801a39857e6b6aebb5153f41deaa12e5fcd2110))
* **helm:** stop podAnnotations from colliding with the metrics annotations ([69b02bc](https://github.com/maltzsama/lakedeepdiver/commit/69b02bcdd149268b73ca8db17afa5356ca07f1a0))
* **spec:** update auth smoke test for the frameless login icon ([7db5fb0](https://github.com/maltzsama/lakedeepdiver/commit/7db5fb089a3a71d7ab7908d68ba8fdf9ed639798))
* **ui:** drop the invert filter and bump the login icon to 96px ([2a555b6](https://github.com/maltzsama/lakedeepdiver/commit/2a555b65d22341116635ea8c0538afe0a9fb5095))
* **ui:** remove the square frame around the login logo ([354dd92](https://github.com/maltzsama/lakedeepdiver/commit/354dd92c3c77127b54d15d5ccdad808cf9651bc7))

## [0.3.0](https://github.com/maltzsama/lakedeepdiver/compare/v0.2.6...v0.3.0) (2026-08-25)


### Features

* **observability:** expose Prometheus metrics and structured JSON logs ([0555416](https://github.com/maltzsama/lakedeepdiver/commit/0555416d3e72e010ff9af304b6ac45874875e0d2))
* **observability:** expose Prometheus metrics and structured JSON logs ([bc9c749](https://github.com/maltzsama/lakedeepdiver/commit/bc9c74912900d6f9b1a443dc29483b4680e38435))

## [0.2.6](https://github.com/maltzsama/lakedeepdiver/compare/v0.2.5...v0.2.6) (2026-08-24)


### Bug Fixes

* **catalogs:** make resolve_s3_credentials exhaustive ([e9fd313](https://github.com/maltzsama/lakedeepdiver/commit/e9fd313627773ec922b36560ec64487ae4ee4e4e))
* CSP, turbo frame dup, and five defensive guards ([eaecb23](https://github.com/maltzsama/lakedeepdiver/commit/eaecb23ffea7c3c5f0b872d5d4355f9125cefd20))
* **engine:** tolerate a finished chain with no maintenance_plan ([aa2bce2](https://github.com/maltzsama/lakedeepdiver/commit/aa2bce2d5d27cfd3fa6396a366b06fdd168a1769))
* **http:** apply timeouts to plain http connections too ([cb9a1e5](https://github.com/maltzsama/lakedeepdiver/commit/cb9a1e554b2f44cd35769d18688aeed3ca6a0a3c))
* **security:** enable Content-Security-Policy in report-only mode ([90877fd](https://github.com/maltzsama/lakedeepdiver/commit/90877fd1fcf3283af68aca0d8c6720b49ee0865d))
* **ui:** remove duplicate nested turbo frame in activity running list ([6330dc7](https://github.com/maltzsama/lakedeepdiver/commit/6330dc7bf3cfe9faa89f6dbf58935a0669e1dd3b))
* **users:** return a validation error instead of raising ([4df028f](https://github.com/maltzsama/lakedeepdiver/commit/4df028fca02b5139999633b667afd6c84f17b0af))

## [0.2.5](https://github.com/maltzsama/lakedeepdiver/compare/v0.2.4...v0.2.5) (2026-08-24)


### Bug Fixes

* **icons:** replace hardcoded SVGs with icon files, add favicon.ico ([2ae5c8c](https://github.com/maltzsama/lakedeepdiver/commit/2ae5c8cbe0e5dd30b01bf4f15998566de844f48c))

## [0.2.4](https://github.com/maltzsama/lakedeepdiver/compare/v0.2.3...v0.2.4) (2026-08-24)


### Bug Fixes

* catalog sync deactivation, error retention, token expiry and four more ([7d7dcdf](https://github.com/maltzsama/lakedeepdiver/commit/7d7dcdfc387010bf13f8c22e864bf79e5484c1bc))
* **catalogs:** honour the OAuth token's real expiry ([73cd371](https://github.com/maltzsama/lakedeepdiver/commit/73cd37135a10318fdcd17a2b5c29d184401b5f8c))
* **catalogs:** stop deactivating tables a failed sync could not see ([d5a4b8b](https://github.com/maltzsama/lakedeepdiver/commit/d5a4b8bfd8c013876ea821cd7f6c880a9103d0cf))
* **engine:** count maintenance rows across every Trino page ([ae39c8b](https://github.com/maltzsama/lakedeepdiver/commit/ae39c8b2b73f439ac853e0d27e158df5d70b2e35))
* **engine:** make the state transition an actual compare-and-set ([b5ff54e](https://github.com/maltzsama/lakedeepdiver/commit/b5ff54e838b29696ad516971dc17cbe3c50a43c0))
* **freshness:** cancel the Trino query a probe stops reading ([4dba160](https://github.com/maltzsama/lakedeepdiver/commit/4dba1609935c1e9ca648b09c71f32787c671ee12))
* **retention:** prune error events by last_seen_at, not created_at ([c18d07c](https://github.com/maltzsama/lakedeepdiver/commit/c18d07c13d968a7c05c77d71d53c4712f189677c))
* **security:** fail loudly when an action forgets to authorize ([48f9c8a](https://github.com/maltzsama/lakedeepdiver/commit/48f9c8a2e52adf365da482c4cd1c8707ac2cf654))

## [0.2.3](https://github.com/maltzsama/lakedeepdiver/compare/v0.2.2...v0.2.3) (2026-08-24)


### Bug Fixes

* **docs:** README as the docs landing page, changelog page, single Pages publisher ([c384f5f](https://github.com/maltzsama/lakedeepdiver/commit/c384f5f8fd2d34e2504eb8e0af5bea71e1efab09))
* **docs:** render the README as the documentation landing page ([6cd514a](https://github.com/maltzsama/lakedeepdiver/commit/6cd514ad1ee18cea0c88997b447179633ea8190d))

## [0.2.2](https://github.com/maltzsama/lakedeepdiver/compare/v0.2.1...v0.2.2) (2026-08-24)


### Bug Fixes

* **catalogs:** take the materialized Secret name and namespace from the chart ([7454a77](https://github.com/maltzsama/lakedeepdiver/commit/7454a77376eb0e00d1d96d6b994db7bdf779fd6b))
* **chart:** close the install blockers found in the second review ([37e6f1b](https://github.com/maltzsama/lakedeepdiver/commit/37e6f1bbd0ca04380d2cb3ae6f72c3688b5938af))
* **engine:** stop leaking demand from an execution whose dispatch never lands ([4ae9138](https://github.com/maltzsama/lakedeepdiver/commit/4ae9138c4bb07cdd54eb41a6d37bda359f1b49aa))
* **engine:** surface Kubernetes failures to the engine start retry ([4d0a41f](https://github.com/maltzsama/lakedeepdiver/commit/4d0a41f82617b9b266890390cc0290fc1cbb6390))
* **plans:** reject a nil maintenance step config instead of raising on it ([3939912](https://github.com/maltzsama/lakedeepdiver/commit/3939912b06edb972a6c4c98d945ca2212246e3eb))

## [0.2.1](https://github.com/maltzsama/lakedeepdiver/compare/v0.2.0...v0.2.1) (2026-08-24)


### Bug Fixes

* **engine:** enqueue maintenance only after the primary transaction commits ([27741f3](https://github.com/maltzsama/lakedeepdiver/commit/27741f325f2d575c392655195cf285d4b9c0b528))
* **engine:** enqueue maintenance only after the primary transaction commits ([ad40c1c](https://github.com/maltzsama/lakedeepdiver/commit/ad40c1c45a5dfdad01fb102696ae932969134b35))
* **engine:** retry the maintenance job when the primary commit is not visible ([a6e0ea9](https://github.com/maltzsama/lakedeepdiver/commit/a6e0ea98829d6c39744ca646637bc91bfadb1926))

## [0.2.0](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.8...v0.2.0) (2026-08-24)


### Features

* **chart:** grant RBAC in the Trino namespace when it differs from release ([5639cf8](https://github.com/maltzsama/lakedeepdiver/commit/5639cf851c216ffafd0d5f48c3b92207c8687cc5))
* **chart:** grant RBAC in the Trino namespace when it differs from release ([e81f034](https://github.com/maltzsama/lakedeepdiver/commit/e81f034fdc5f1f884b166baa64c17f15a06c0957))

## [0.1.8](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.7...v0.1.8) (2026-08-24)


### Bug Fixes

* **helm:** bootstrap admin login, skip web db:prepare, stop overriding SSL bundle ([3af64f8](https://github.com/maltzsama/lakedeepdiver/commit/3af64f850072d04ea245cb5f41af452217002bcb))
* **helm:** bootstrap admin login, skip web db:prepare, stop overriding SSL bundle ([58a7eae](https://github.com/maltzsama/lakedeepdiver/commit/58a7eaefeb9b490a1bb768767631b0e1a9fa1169))

## [0.1.7](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.6...v0.1.7) (2026-08-24)


### Bug Fixes

* **ci:** download only the chart and docs artifacts in the pages job ([3ab881f](https://github.com/maltzsama/lakedeepdiver/commit/3ab881f18416fde218bee01ea55b5ee879bfc29d))
* **ci:** download only the chart and docs artifacts in the pages job ([c3ce7a6](https://github.com/maltzsama/lakedeepdiver/commit/c3ce7a6e7849722f054465e6a763af4a2840a70c))

## [0.1.6](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.5...v0.1.6) (2026-08-24)


### Bug Fixes

* **ci:** upload a clean chart index so the release pages job works ([09ff806](https://github.com/maltzsama/lakedeepdiver/commit/09ff806adc60213bf92f17967f8c522ea541adb0))
* **ci:** upload a clean chart index so the release pages job works ([2fc5b78](https://github.com/maltzsama/lakedeepdiver/commit/2fc5b785069cb52838c823cb92fc49a8faf1a40e))

## [0.1.5](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.4...v0.1.5) (2026-08-24)


### Bug Fixes

* **security:** scope secret RBAC and validate maintenance step config ([2274bb8](https://github.com/maltzsama/lakedeepdiver/commit/2274bb8b10a130e2910b1fffad8ad0abd702e54e))
* **security:** scope secret RBAC and validate maintenance step config ([8ddeab4](https://github.com/maltzsama/lakedeepdiver/commit/8ddeab407d8c1fc3dcfc76ceed062f65dc5d1552))

## [0.1.4](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.3...v0.1.4) (2026-08-24)


### Bug Fixes

* **chart:** close the env gaps that block a working install ([5069c53](https://github.com/maltzsama/lakedeepdiver/commit/5069c53b133b4647267cffca052e36ffa7ccb42d))
* **chart:** close the env gaps that block a working install ([7549353](https://github.com/maltzsama/lakedeepdiver/commit/7549353fdad49deaf120c674f61bff88ebd91402))

## [0.1.3](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.2...v0.1.3) (2026-08-24)


### Bug Fixes

* **k8s:** authenticate TrinoSecretMaterializer to the API ([3d85e18](https://github.com/maltzsama/lakedeepdiver/commit/3d85e18b9f2202a1eeadff0e8867d791436908fc))
* **k8s:** authenticate TrinoSecretMaterializer to the API ([14d8be5](https://github.com/maltzsama/lakedeepdiver/commit/14d8be5c2aa669e7020763e76209acd4a071d336))
* **k8s:** avoid KeyError for API endpoint outside the cluster ([163483a](https://github.com/maltzsama/lakedeepdiver/commit/163483a3d8c6cdcd25295519dba093fc88103398))

## [0.1.2](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.1...v0.1.2) (2026-08-24)


### Bug Fixes

* **engine:** reap running executions with NULL heartbeat ([d271916](https://github.com/maltzsama/lakedeepdiver/commit/d2719160490da2722f2fe9c7c09a036664bba254))
* **engine:** reap running executions with NULL heartbeat ([68aed38](https://github.com/maltzsama/lakedeepdiver/commit/68aed38ea61604633303b20ae2cc58f03ff1bcfd))

## [0.1.1](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.0...v0.1.1) (2026-08-23)


### Bug Fixes

* **projection:** omit rest-catalog warehouse for Nessie catalogs ([ac7c506](https://github.com/maltzsama/lakedeepdiver/commit/ac7c5061fe30ab5214b577dd3e8f79251a85f819))

## 0.1.0 (2026-08-23)


### Features

* account profile with locale, theme and password preferences ([ffabd56](https://github.com/maltzsama/lakedeepdiver/commit/ffabd560e2dcc25d218c85ab49c6a036b3a8a8ad))
* add admin alert channels, settings and freshness SLA UI ([082e6fb](https://github.com/maltzsama/lakedeepdiver/commit/082e6fba3c9acc73600a0ddebb4d9a354cbe0aa2))
* add alert channels, settings and freshness severity models ([c3be446](https://github.com/maltzsama/lakedeepdiver/commit/c3be446522fb8a905b17db51d8daf1d635b31bf3))
* add alert mailer and channel notifier ([7fb75c5](https://github.com/maltzsama/lakedeepdiver/commit/7fb75c5bcf1501d4f9a81f9718a302bbd4c23974))
* add configurable where and snapshot_ids to maintenance steps ([e7f1bb3](https://github.com/maltzsama/lakedeepdiver/commit/e7f1bb37be2c3a21fe99f6f5550d3bf021926c34))
* add devise user auth and Iceberg data model ([f47029c](https://github.com/maltzsama/lakedeepdiver/commit/f47029c2452065c1eaf5971f96b54d720c156b9e))
* add Helm chart for on-prem deployment ([f091b4a](https://github.com/maltzsama/lakedeepdiver/commit/f091b4a8da29a3feadbc920d09f9da5b2ab368fc))
* add management UI with admin RBAC ([1eba165](https://github.com/maltzsama/lakedeepdiver/commit/1eba165be47964150b9aa526a6b15bc6b80f09f3))
* add profile dropdown menu with sign out to topbar ([70eb624](https://github.com/maltzsama/lakedeepdiver/commit/70eb6241022e0f02a8e24c61c4f7b7a0951baceb))
* apply engine config changes to running cluster immediately ([afe9d43](https://github.com/maltzsama/lakedeepdiver/commit/afe9d43c76498cbc8c3754769aa78a5a36db09e9))
* authorize user/team admin and let operators run maintenance ([856d766](https://github.com/maltzsama/lakedeepdiver/commit/856d766122e5a50bf2c86230b7b6be649c3b4c27))
* broadcast the solid queue backlog on the activity screen ([ac3c502](https://github.com/maltzsama/lakedeepdiver/commit/ac3c502f0ee9ebdd33d3e422ec37fd306f50f555))
* cancel a trino query from the activity screen ([5b764f5](https://github.com/maltzsama/lakedeepdiver/commit/5b764f5209ca7da5e3a68d604d0d6e7d4bb2f3e1))
* cancel queued executions and allow operators to cancel ([68485b2](https://github.com/maltzsama/lakedeepdiver/commit/68485b2ce5efe7639f16d8bc95d72a860e0b5ee2))
* capture trino query id and live progress during maintenance ([ed1421d](https://github.com/maltzsama/lakedeepdiver/commit/ed1421d1315dc6498ef3a7d2acb6f2494427842c))
* catalog credentials, derived Trino catalog name, root-failure propagation ([c226c6d](https://github.com/maltzsama/lakedeepdiver/commit/c226c6d2ff3dca3def5efa365a256c84c55baf12))
* **catalogs:** auth strategies with RFC 8693 token exchange (CR-A-WW + VV delta) ([e266fc1](https://github.com/maltzsama/lakedeepdiver/commit/e266fc16f744e8cce7015cc3522df27a3280225f))
* **catalogs:** CR-A-ZZ - Nessie over Iceberg REST with config-driven prefix ([9a9717d](https://github.com/maltzsama/lakedeepdiver/commit/9a9717d082118e4c477224373cbd1b9d6cb765a3))
* configurable Trino engine topology + activity UI polish ([bf69291](https://github.com/maltzsama/lakedeepdiver/commit/bf69291cfadc79b0eccdc8b2c3edbfdbc3c95ed1))
* cosmonaut dark theme with sidebar and topbar shell ([a52f38c](https://github.com/maltzsama/lakedeepdiver/commit/a52f38c55621865337e0a81823d923b4b583b86d))
* **dashboard, freshness:** needs-action feed with errors, per-table SLA affordances ([6457c21](https://github.com/maltzsama/lakedeepdiver/commit/6457c21b2ae1f0adaf452a9eddf51e9431e7a60a))
* drive the real Trino runtime on Kubernetes ([7994c99](https://github.com/maltzsama/lakedeepdiver/commit/7994c992c3db6516022d8e72273ea0e84b9ffd37))
* edit maintenance plan schedule and step chain ([b5109bd](https://github.com/maltzsama/lakedeepdiver/commit/b5109bdff4aed7f0351b817ee85398312112b136))
* engine guard-rail with two demand sources ([5e6e8bf](https://github.com/maltzsama/lakedeepdiver/commit/5e6e8bf5d79dfb125ba9973ae783ed6e21eac1f0))
* engine hard reset, engine history at page bottom, tables sync, helm README ([dd4dcf3](https://github.com/maltzsama/lakedeepdiver/commit/dd4dcf3a680bb220cabed999a13b5f2a18c8e7d1))
* **error_events:** detail page with assign/acknowledge/resolve workflow and teams ([f39bdb2](https://github.com/maltzsama/lakedeepdiver/commit/f39bdb2614efcf5cab67963a0eb378d4b19aa8dd))
* escalate freshness severity by delay ([b9ad89d](https://github.com/maltzsama/lakedeepdiver/commit/b9ad89d6355f5bcefa1bceee3b18ea6e8eb9d94a))
* **execution_steps:** split skip_reason from error_message, add blocked status (CR-E-YY) ([47827ad](https://github.com/maltzsama/lakedeepdiver/commit/47827ad48c3cc675a18ed0c482ae5497f5e70ac8))
* expose run maintenance to operators on tables and plans ([b29cfd1](https://github.com/maltzsama/lakedeepdiver/commit/b29cfd13237a52ed115938c8ea083eed654b1daa))
* filter inactive tables in the UI and skip them in freshness and dispatch ([598f3ce](https://github.com/maltzsama/lakedeepdiver/commit/598f3ce63bd7f85266d63e26071a476210c0437a))
* freshness as its own dimension ([cfb0637](https://github.com/maltzsama/lakedeepdiver/commit/cfb0637bda727e6ac00eb2f8e8a9fd42d02cada2))
* freshness in the tables list and on the table page ([ec30ad5](https://github.com/maltzsama/lakedeepdiver/commit/ec30ad59f5f5e7d4eac6311098c5b30fd71d8675))
* full table metadata collection and a rebuilt health score ([64ef79a](https://github.com/maltzsama/lakedeepdiver/commit/64ef79aadd988dd32959c816af92a20a010fe6ae))
* global header navigation, session controls and tidy flashes ([4edfac6](https://github.com/maltzsama/lakedeepdiver/commit/4edfac6c853d0a2bc46babaa17d6f7d61c6f49fa))
* **helm:** publish chart for public distribution (CR-H-01) ([d395892](https://github.com/maltzsama/lakedeepdiver/commit/d395892ad679730ee372a884fe5abfc3cea63e7a))
* **i18n:** replace hardcoded strings with t() calls and complete pt-BR translations ([8f485a0](https://github.com/maltzsama/lakedeepdiver/commit/8f485a0a77b3ff61a48fda933692c59ce7c438e4))
* in-progress screen and renamed navigation ([28b2064](https://github.com/maltzsama/lakedeepdiver/commit/28b206481bd2a2abc87510878bf897b18f5bf061))
* maintenance plans with an ordered chain of steps ([ad0b5ce](https://github.com/maltzsama/lakedeepdiver/commit/ad0b5ce7363a777a1212659e688e3bddcc146ab6))
* maintenance policies - one rule for many tables ([fb0dd12](https://github.com/maltzsama/lakedeepdiver/commit/fb0dd12d8c60c1b4f729db61747894e583a321dc))
* metadata tabs, operator actions and the policy explainer ([cadd664](https://github.com/maltzsama/lakedeepdiver/commit/cadd6648645e4add56412180c9dbc5cebd63aaea))
* migrate the UI foundation to Tailwind CSS ([2a851a7](https://github.com/maltzsama/lakedeepdiver/commit/2a851a76cebbe2327858c48536830bb0de02a4bf))
* move freshness alert destination to the SLA ([d7f1878](https://github.com/maltzsama/lakedeepdiver/commit/d7f18789cfe2c078ac18b70d27cd09c10e3af72f))
* OIDC sign-in on by default, public registration closed ([6598dc6](https://github.com/maltzsama/lakedeepdiver/commit/6598dc6f705fa861b8e00b6c735e2aef9a069dfd))
* **operations:** CR-E-XX v4 - one block per execution with timeline bar ([e2e6d5a](https://github.com/maltzsama/lakedeepdiver/commit/e2e6d5a7ff5d71913b4e2a9fa80b4667fae0a713))
* orchestrate maintenance runs over Solid Queue ([8a34e0d](https://github.com/maltzsama/lakedeepdiver/commit/8a34e0d7ef62920928ee78cbcf692e3d1ccaad48))
* **orchestrator:** skip_reason on ExecutionHistory + table-level run guard ([b6b13d3](https://github.com/maltzsama/lakedeepdiver/commit/b6b13d303985ca8c537f2458a7cc592a065c0628))
* per-step cadence in maintenance plans ([d441867](https://github.com/maltzsama/lakedeepdiver/commit/d441867b8d219b680264a397b2bcfc440a32cf2b))
* policies manage whole maintenance chains ([e2bd75b](https://github.com/maltzsama/lakedeepdiver/commit/e2bd75b7e4d061efb1423470f3c6c7c981ea2f9b))
* provision trino catalogs through the baleia registry ([0f67db6](https://github.com/maltzsama/lakedeepdiver/commit/0f67db6a5babd9263d9fa2415c356ed3fd93252e))
* **queues:** separate engine lifecycle into its own queue and worker ([887b313](https://github.com/maltzsama/lakedeepdiver/commit/887b313e8508acdec9819f18f69ec2cfa5b6eeb1))
* record engine lifecycle and drain failures as error events ([a47ba1c](https://github.com/maltzsama/lakedeepdiver/commit/a47ba1caa3718d585069d6a87d8a18bffe7a2c33))
* record error events and triage tables needing maintenance ([7211764](https://github.com/maltzsama/lakedeepdiver/commit/72117641c106792b48d831308cc6f58f8b2059da))
* replace activity-screen meta-refresh with Turbo Streams broadcasts ([1b7f9a5](https://github.com/maltzsama/lakedeepdiver/commit/1b7f9a5ae581dc4356e9e1889b383853df988881))
* replace require_admin! with pundit policies across controllers ([7ac9b92](https://github.com/maltzsama/lakedeepdiver/commit/7ac9b92761247b39beca91e6d5e7248542d2c3cb))
* **s3:** STS AssumeRole and per-catalog S3 storage auth ([f231de3](https://github.com/maltzsama/lakedeepdiver/commit/f231de36de94586413816914c7b2ec1eab7c8c40))
* **secrets:** catalog credentials move to K8s Secret with file references ([62df68f](https://github.com/maltzsama/lakedeepdiver/commit/62df68fc75c19d844f73878ffd40f00a8c421c85))
* separate engine lifecycle from execution ([b3b0e61](https://github.com/maltzsama/lakedeepdiver/commit/b3b0e6156348b56ef4880c6eb8707e91cc5ab765))
* show trino query id and metrics in the operations history ([ac673f5](https://github.com/maltzsama/lakedeepdiver/commit/ac673f578cdf4d6d109951c3e22a32a34d382d48))
* soft-delete dropped tables and sync catalogs every 6h ([78b94d8](https://github.com/maltzsama/lakedeepdiver/commit/78b94d8d9280b6e5896d71a9d01a6266bcdf87fb))
* surface active queries, queue and engine timeline on the activity screen ([5b63c7d](https://github.com/maltzsama/lakedeepdiver/commit/5b63c7df38fee4adc82267a525f5bcf51eda7227))
* sync Iceberg catalogs and score table health ([71a3d9d](https://github.com/maltzsama/lakedeepdiver/commit/71a3d9d5a2738aa095a61c1efe868d46bdcab041))
* tables list and operations log on the chain model ([0b8c768](https://github.com/maltzsama/lakedeepdiver/commit/0b8c768096019269c8b05984a324fa15fa5b1560))
* teams, memberships and user administration data model ([f5747dc](https://github.com/maltzsama/lakedeepdiver/commit/f5747dc3e4d176ca5d81af8005e13d17290e2f28))
* **ui:** app layout with navigation, session and helpers ([50af4fa](https://github.com/maltzsama/lakedeepdiver/commit/50af4fa354943e0239410d941d7a745cebee6500))
* **ui:** dedicated split-screen auth layout ([8782fda](https://github.com/maltzsama/lakedeepdiver/commit/8782fdada7d2baecbc332df5a668e08215255793))
* **ui:** global operations log ([561de7c](https://github.com/maltzsama/lakedeepdiver/commit/561de7c2bbcb95872ce1ff50b7459b796179e699))
* **ui:** global tables view with filters ([bbaaa92](https://github.com/maltzsama/lakedeepdiver/commit/bbaaa92a52dd63286ab9a1b1e19539136e066524))
* **ui:** health summary cards and data freshness on the dashboard ([b186b45](https://github.com/maltzsama/lakedeepdiver/commit/b186b450c12da35b367124d057cba6b13f78efe9))
* **ui:** rewrite existing views with the design system ([c2dbb9e](https://github.com/maltzsama/lakedeepdiver/commit/c2dbb9e88e1a1e9ed9a1542e57084941effb4ab2))
* **ui:** shared partials and the execution step chain ([b14e0c3](https://github.com/maltzsama/lakedeepdiver/commit/b14e0c33ef0eaff97506c9fea7af58f17d52bec9))
* **ui:** style the Devise screens ([23a92c8](https://github.com/maltzsama/lakedeepdiver/commit/23a92c8e277bdc32bb1bb69a20bb62fc541186b9))
* **ui:** Tailwind design tokens, component classes and i18n base ([33e740f](https://github.com/maltzsama/lakedeepdiver/commit/33e740f20faf91ce1e803807625b67621342771b))
* unify maintenance and freshness scans in one operation feed ([8a05e67](https://github.com/maltzsama/lakedeepdiver/commit/8a05e67cdfec299ce57886ae3307d190ce906bcd))
* user and team administration screens ([29ec305](https://github.com/maltzsama/lakedeepdiver/commit/29ec305b8b21ab383a9fc393e9c104aed67e2d1a))


### Bug Fixes

* add \z anchor to catalog endpoint format validation (Brakeman ValidationRegex) ([11fb90d](https://github.com/maltzsama/lakedeepdiver/commit/11fb90d7c76ad7a49bfa1bfe1d6bbcbadeaaee34))
* add bulk acknowledge/resolve UI for error events ([3c9ec20](https://github.com/maltzsama/lakedeepdiver/commit/3c9ec20b1e4a8738b1c7a0bdfe4ede0783dc42d9))
* add confirmation before changing user role ([1c1f0d8](https://github.com/maltzsama/lakedeepdiver/commit/1c1f0d8bb4460d54b54eaa133c4ab6fd92502732))
* add confirmation dialog before pausing a maintenance plan ([ffe38ea](https://github.com/maltzsama/lakedeepdiver/commit/ffe38eab0f58a1407d5209088385b6a306e8b605))
* add daily data retention job for unbounded tables ([193ee9e](https://github.com/maltzsama/lakedeepdiver/commit/193ee9eb675ed4b6b923a46d40dc091e1ac73b13))
* add Devise timeoutable and lockable to User model ([62105ac](https://github.com/maltzsama/lakedeepdiver/commit/62105ac2626ee7d09e28e909d6464e8c1dfdeb1d))
* add missing database indexes for common query patterns ([a33c665](https://github.com/maltzsama/lakedeepdiver/commit/a33c66523bd79b90347c5ecfee70ededd401bae6))
* add missing plans.edit.errors translation key ([61ad876](https://github.com/maltzsama/lakedeepdiver/commit/61ad8762d20979956966ccb136183eb462c342f7))
* add pagy pagination and includes for error_events index\n\nReplaces hard .limit(200) with pagy cursor pagination (50/page\nby default), adds includes(:catalog) to eliminate the per-row N+1\non the error events list, and renders a pagination nav. ([c927af8](https://github.com/maltzsama/lakedeepdiver/commit/c927af89839e4be60c2f08b44b4333ba6955df0e))
* add retry_on to ApplicationJob and engine watchdog for stuck states ([e1cdf12](https://github.com/maltzsama/lakedeepdiver/commit/e1cdf120464f9f2c00a702157080d5c02a592176))
* add SSRF protection on catalog endpoint URLs ([7735132](https://github.com/maltzsama/lakedeepdiver/commit/773513272d06ed96038cf7c4cd211117873e0bff))
* add status guards to prevent execution state clobbering ([c1d4150](https://github.com/maltzsama/lakedeepdiver/commit/c1d4150432b446c4ebbb8856070972e9a1ae2117))
* add trailing newline to triage query spec ([8e6a1a2](https://github.com/maltzsama/lakedeepdiver/commit/8e6a1a2452aacb4b35117d4387b37ae9499b43f1))
* auto-refresh the activity screen only while visible, drop the nav badge ([f31a0bc](https://github.com/maltzsama/lakedeepdiver/commit/f31a0bcccbd92e484662075aa034a7d22b94c73c))
* CAS on transition!, broadcast outside lock, guard restart!, zero-demand recheck ([cfbb99e](https://github.com/maltzsama/lakedeepdiver/commit/cfbb99eb4c85b25e69b02e9ebe286007f092f08c))
* **ci:** GitHub Pages via Actions, not branch ([cbaa110](https://github.com/maltzsama/lakedeepdiver/commit/cbaa110325f312701a7d5993f9f37c842b6896a3))
* **ci:** inject artifacthub-repo.yml via ARTIFACTHUB_REPO_ID variable ([bbe26a5](https://github.com/maltzsama/lakedeepdiver/commit/bbe26a5f6738725b12aa9c3b442263650b229166))
* **ci:** remove ct lint from chart job (helm lint + kubeconform sufficient) ([6d0f5fd](https://github.com/maltzsama/lakedeepdiver/commit/6d0f5fd33ffbb2edf0ab7e7b721c00ecc5c69a0b))
* **ci:** resolve brakeman warning, helm lint, schema-portability job ([14c84b8](https://github.com/maltzsama/lakedeepdiver/commit/14c84b80b9e9cae74d8b3ef815702bd3e6b71941))
* correct env var defaults in README to match code ([170f1d8](https://github.com/maltzsama/lakedeepdiver/commit/170f1d8cde6e63c2555054ba1622fc6bfe228852))
* define ChartTrinoProvisioner#replicas (engine start crash) ([1ef59d9](https://github.com/maltzsama/lakedeepdiver/commit/1ef59d997b682ead370b8f6990a73ef6963a6940))
* derive trino catalog names against the plugin schema ([aa6b995](https://github.com/maltzsama/lakedeepdiver/commit/aa6b9956f8bfaaa9fbe964d91980e1297c299be7))
* do not pile up duplicate runs when 'run now' is clicked repeatedly ([b3d0abb](https://github.com/maltzsama/lakedeepdiver/commit/b3d0abb885dbd9ea343bd915c55a2d1b4f0736fa))
* **docs:** read counter.dev data-id from DATA_TRACKING secret ([e4e19eb](https://github.com/maltzsama/lakedeepdiver/commit/e4e19ebe8187e2250dbb33f25a7d999f97d38b21))
* **docs:** remove DATA_TRACKING fallback, fail if env var missing ([be40596](https://github.com/maltzsama/lakedeepdiver/commit/be40596a066b9cb377013f4c9c75c59e4c30a77d))
* eager-count schedules in the catalog tables list and fix viewer table header ([0d7297b](https://github.com/maltzsama/lakedeepdiver/commit/0d7297b61c6bbabafa8fcde13047dc88033bbda3))
* emit 3-part Trino identifiers and sync nested namespaces ([85c15fd](https://github.com/maltzsama/lakedeepdiver/commit/85c15fd7f25eec2d7354a89d9f8ed1e68f92c168))
* enable cancel button on running executions in live view ([e7ea9bd](https://github.com/maltzsama/lakedeepdiver/commit/e7ea9bd90be680a4cb0e3de389acb84aa0207b91))
* enable force_ssl and host authorization in production ([d7265c9](https://github.com/maltzsama/lakedeepdiver/commit/d7265c9c0f1a1ad53cde06015528e1f12b6b854d))
* filter catalog registry secrets from inspect/logs ([00f5df4](https://github.com/maltzsama/lakedeepdiver/commit/00f5df4436f1848d51987f6749ddd6a5bfbe19a9))
* **freshness:** heartbeat on FreshnessRun so sweep is not reaped mid-flight ([e0c4a74](https://github.com/maltzsama/lakedeepdiver/commit/e0c4a744977555a525f7ac1d83935ed88c89a391))
* **grants:** baleia_reader → baleia_trino with DML on registry ([ed5fabf](https://github.com/maltzsama/lakedeepdiver/commit/ed5fabf99b75a5b5538724d560c586022858acb1))
* guard helpers and broadcasts from missing request context ([2c1e0c0](https://github.com/maltzsama/lakedeepdiver/commit/2c1e0c033cd49d3c627f86c21497ba96f76be306))
* **history, pager:** query id last in step meta; pager active-page bug ([c9c7285](https://github.com/maltzsama/lakedeepdiver/commit/c9c7285b391efe47d4a91ec80a91c756803cd8c5))
* **i18n:** auth methods nesting, 31 missing pt-BR keys, time formats ([751ad85](https://github.com/maltzsama/lakedeepdiver/commit/751ad857abd22a6c5fa21e0a0b0ff1f8de1ea312))
* **job:** isolate schedule failures to prevent cascade blocking ([abc6a4e](https://github.com/maltzsama/lakedeepdiver/commit/abc6a4eb3aac20e0dc6a3c63fa1b71371cbaaacb))
* keep syncing the catalog when one table or namespace fails ([2bb7c8f](https://github.com/maltzsama/lakedeepdiver/commit/2bb7c8f491ee3b8bb3f2382a03204c326c55fcff))
* keep Trino up and the lock held while a maintenance awaits retry ([387aea5](https://github.com/maltzsama/lakedeepdiver/commit/387aea573e7a357bbf46eb643a8ffa8818667749))
* load dashboard.css via application.css and fix the layout tag ([2af5710](https://github.com/maltzsama/lakedeepdiver/commit/2af571048ad1f8c392db99a10a56865cd9c8c3c7))
* make the activity Refresh now a button instead of a link ([bed948b](https://github.com/maltzsama/lakedeepdiver/commit/bed948b1953773f05be8e7b12022ab9512c87cc0))
* make the table run-now button self-sufficient on Postgres ([0ad7836](https://github.com/maltzsama/lakedeepdiver/commit/0ad78360b52a0649e452ba6ad9ca1779032ff1fa))
* **materializer:** gracefully skip K8s secret creation on SSL failure ([913d055](https://github.com/maltzsama/lakedeepdiver/commit/913d0554e8341430d4c940645ba26b53c5de3397))
* move all hardcoded flash notices to i18n ([004403e](https://github.com/maltzsama/lakedeepdiver/commit/004403ea2f66206082f383ae3a1396bf5a1fb8ca))
* notify the engine supervisor when demand drops after a failure ([4a6c9ef](https://github.com/maltzsama/lakedeepdiver/commit/4a6c9ef40fa535231b4079bdf4cdbf47d5a457b6))
* **pages:** use rake docs:build to inject counter.dev tracking ([96677c8](https://github.com/maltzsama/lakedeepdiver/commit/96677c876e5d1088f6dc42187b210e8c36600ccd))
* **pagy:** remove grouped relation that broke table listing ([24c5c64](https://github.com/maltzsama/lakedeepdiver/commit/24c5c64c397e95786846284fd1ae9fbd927d3129))
* paper/ink layout regressions, nav active state and combobox styling ([5de844f](https://github.com/maltzsama/lakedeepdiver/commit/5de844f22c5b7e34b63f6c57b1541898ec2d8a96))
* parse URI strings in HttpTransport before building requests ([91c619a](https://github.com/maltzsama/lakedeepdiver/commit/91c619a6ff12b1cf055f1c435ab7431ec014411c))
* permit saving schedules with empty config fields ([a93f7c9](https://github.com/maltzsama/lakedeepdiver/commit/a93f7c9a29753b97288690d55b3c546bfb7ee9ae))
* persist sidebar collapsed state across navigations ([f908e50](https://github.com/maltzsama/lakedeepdiver/commit/f908e5057ebb8c531a7d843a0f82a7767220adf5))
* poll Trino nextUri in a loop with backoff and a deadline ([e012808](https://github.com/maltzsama/lakedeepdiver/commit/e0128085e28cdfcf4cfa24c22a548b45c6a5d401))
* preserve success status when the scale-down teardown fails ([52cd540](https://github.com/maltzsama/lakedeepdiver/commit/52cd54082ee7d8358a415507b1f4134896c4a360))
* profile params key mismatch (user vs profile) + add ruby-vips ([28dfbcb](https://github.com/maltzsama/lakedeepdiver/commit/28dfbcba4024178ae5928acef7dbfaa2291fc26b))
* release table locks on success and stop polluting the error surface ([669032d](https://github.com/maltzsama/lakedeepdiver/commit/669032d2154c26a6fd6238355156bba86d764b39))
* **release:** correct first release version and consolidate publish into release run ([83eb962](https://github.com/maltzsama/lakedeepdiver/commit/83eb96216ec366646294b5ada0743a32d631d739))
* **release:** critical production blockers — queue isolation, DB provisioning, SSO, email alerts ([d6ae4f8](https://github.com/maltzsama/lakedeepdiver/commit/d6ae4f81b4a624982b4ddf7ef3c9308204ab7ae6))
* **release:** initial version 0.1.0 + consolidated publish pipeline ([4d69f5c](https://github.com/maltzsama/lakedeepdiver/commit/4d69f5cf35e307f3053bc6f93e4f9292cd198e77))
* **release:** reset manifest to 0.0.0 for correct first release ([8c926ed](https://github.com/maltzsama/lakedeepdiver/commit/8c926ed81ce97fc9cc51ffc213c1f6dd04566644))
* remove image_processing/ruby-vips to fix CI ([4a92012](https://github.com/maltzsama/lakedeepdiver/commit/4a92012f72a658baf14982920e52692191508039))
* remove unused team scoping code (dead code / IDOR risk) ([eeed868](https://github.com/maltzsama/lakedeepdiver/commit/eeed86841de55a4fe7c7b5bd32ae03c3876214e5))
* remove wildcard queue, use explicit named queues in Solid Queue ([1cf8994](https://github.com/maltzsama/lakedeepdiver/commit/1cf8994930922ec961a7f4a1fc9d73ac700ed021))
* render engine lifecycle history as a proper labeled table ([809d1bc](https://github.com/maltzsama/lakedeepdiver/commit/809d1bc459a2cf800d22ff9fff513a84c5019019))
* **retention:** cascade FK on execution_steps/table_locks so prune never halts ([131ccd8](https://github.com/maltzsama/lakedeepdiver/commit/131ccd8ca3b062982faa1310ffa1f41892044e55))
* run against a real Trino cluster (k8s client, statement body, catalog warehouse) ([3423d81](https://github.com/maltzsama/lakedeepdiver/commit/3423d81b138c0cc188a16770c5071c5fc73f3b53))
* run maintenance redirects back to the current page, not the table detail ([491c222](https://github.com/maltzsama/lakedeepdiver/commit/491c222dc71ebde68864bfbef09d793f557d2ced))
* **schema:** drop GLOB check constraint, add Ruby validations, CI portability guard ([fd6c5e4](https://github.com/maltzsama/lakedeepdiver/commit/fd6c5e4270738a47e84e5024c891b884cc468464))
* **security:** document plaintext credentials, add serializable_hash, plugin role grants ([99fe7ba](https://github.com/maltzsama/lakedeepdiver/commit/99fe7bab86474eaa1513dd230e977cbcb1d086bf))
* send raw SQL body to Trino instead of JSON envelope ([d3a528c](https://github.com/maltzsama/lakedeepdiver/commit/d3a528caa10f7a626841beabbfe4998a0e683dd2))
* show the correct engine start attempt count ([cdaba39](https://github.com/maltzsama/lakedeepdiver/commit/cdaba39d583b3927a60012b54411f42ebbce5b34))
* show the tables count as a number, not a grouped hash ([92a568a](https://github.com/maltzsama/lakedeepdiver/commit/92a568a15e778c76ebea8db3eeb5089aa4c1059e))
* show the trino cluster name in the overview ([99b958e](https://github.com/maltzsama/lakedeepdiver/commit/99b958eea329d302e5468f1c4f16bfd2d23b37ff))
* slash engine startup waste, broadcast 'up', and tidy the activity screen ([97d01b9](https://github.com/maltzsama/lakedeepdiver/commit/97d01b98fc8c5c07c6c37758625db1c516af6ded))
* spec failures + Rack deprecation ([de5e434](https://github.com/maltzsama/lakedeepdiver/commit/de5e4342160c19ccee32e424f4423c69f1de16eb))
* start the scale-up timeout when scaling starts, not at creation ([6920443](https://github.com/maltzsama/lakedeepdiver/commit/6920443a3a4aebbde707a0ca573aace1f3e19946))
* stub AlertSetting.instance in alert_notifier_spec ([d040c5e](https://github.com/maltzsama/lakedeepdiver/commit/d040c5e82e8f3ee2ee7f715c66317452b9e3b493))
* **tests:** add config stubs to CatalogClientTest for prefix discovery ([8b66caf](https://github.com/maltzsama/lakedeepdiver/commit/8b66caf09e740a55a25d5860d05139e156e4bf36))
* **trino:** accumulate rows across pagination pages in poll ([ae284d6](https://github.com/maltzsama/lakedeepdiver/commit/ae284d6a00ad3e5f5f05578fec10d0e64ef1d692))
* trust the internal company CA for HTTPS calls ([52e2cf9](https://github.com/maltzsama/lakedeepdiver/commit/52e2cf94b256cb3d3b678f6b1e79b7da907fb26e))
* use optimize_manifests as the Trino procedure name ([efac776](https://github.com/maltzsama/lakedeepdiver/commit/efac7763cddcb9efdaee894336da18912ed32870))
* use white inputs and neutral groups in the paper theme ([ad537a7](https://github.com/maltzsama/lakedeepdiver/commit/ad537a79502f52e11bbbe662eac5afd24b41103a))
* **ux:** submit-disable, pagination, accessibility, release config ([ac50e04](https://github.com/maltzsama/lakedeepdiver/commit/ac50e04f1314f95ae5fadbd4df718301e2c7a531))
* validate cron expressions with Fugit instead of a hand-rolled regex ([4122645](https://github.com/maltzsama/lakedeepdiver/commit/41226451eaf4e6f001e1ced38188849cdc984099))
* wire ScheduleDispatchJob into recurring schedule ([ff4a083](https://github.com/maltzsama/lakedeepdiver/commit/ff4a083ecc360be77f8fd175e108fd81f4692e71))

## [Unreleased](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.0...HEAD)

### Features

- **orchestrator**: skip_reason on ExecutionHistory + table-level run guard
- **queues**: separate engine lifecycle into its own queue and worker
- **s3**: STS AssumeRole and per-catalog S3 storage auth
- **dashboard, freshness**: needs-action feed with errors, per-table SLA affordances
- **catalogs**: Nessie over Iceberg REST with config-driven prefix
- **catalogs**: auth strategies with RFC 8693 token exchange
- **operations**: one block per execution with timeline bar
- **execution_steps**: split skip_reason from error_message, add blocked status
- **error_events**: detail page with assign/acknowledge/resolve workflow and teams

### Bug Fixes

- **retention**: cascade FK on execution_steps/table_locks so prune never halts
- **freshness**: heartbeat on FreshnessRun so sweep is not reaped mid-flight
- **trino**: accumulate rows across pagination pages in poll
- **history, pager**: query id last in step meta; pager active-page bug
- **docs**: read counter.dev data-id from DATA_TRACKING secret
- **catalog endpoint format validation**: add \z anchor (Brakeman ValidationRegex)
- **helpers and broadcasts**: guard from missing request context
- **user role**: add confirmation before changing
- **flash notices**: move all hardcoded to i18n
- **maintenance plan**: add confirmation dialog before pausing

### Refactoring

- **trino**: poll with early-stop limit instead of blind row accumulation
- **catalogs**: drop the path_prefix legacy regime - discovery is the only path
- **history, errors**: step subrows, real filters and a proper pager

### Chores

- ignore dump artifacts
- **error_events**: tighten detail page typography
- **teams**: match project design system on assignment and team forms

## [0.1.0](https://github.com/maltzsama/lakedeepdiver/releases/tag/v0.1.0) - 2026-08-09

### Added

- Initial release: Rails 8 control plane for Iceberg table maintenance.
