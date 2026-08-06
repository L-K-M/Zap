# SHARED-ICONS — one icon change, three apps

*A research study, August 2026. Nothing here is implemented. This document asks
whether Zap, Jetty and Top Drawer can share a single way to change an app's icon,
concludes that they can, and works out which of the five available mechanisms is
the right one and what it would cost.*

**Verification caveat** (inherited from `UNJAILED.md` and `ANALYSIS.md`): written
without a macOS toolchain or a Tahoe machine. Claims about system behaviour carry
confidence markers. The load-bearing ones are collected in §9.

---

## 1. The question

Three apps in this family draw app icons, and two of them let the user change one:

| | Draws app icons | Lets you change them |
|---|---|---|
| **Zap** — ⌘-Tab switcher | ✅ every running app | ✅ per app, with un-jailing, themes and search |
| **Jetty** — Dock replacement | ✅ every pinned tile | ✅ per dock item, "Set Custom Icon…" |
| **Top Drawer** — edge-tab launcher | ✅ every drawer item | ✅ per drawer item, image file or generated |

Each change is local to the app that made it. Give Safari a custom icon in Zap and
Jetty's dock still shows the system's. The question is whether one change can apply
in all three.

The answer is yes, by four different mechanisms, three of which are viable. The
interesting part is that "shared" turns out to mean three separable things, and the
best answer does two of them and defers the third.

---

## 2. What the three apps do today

All three ultimately call `NSWorkspace.icon(forFile:)` for their default artwork,
which on macOS 26 hands back the squircle-masked composite. So all three are jailed
today; only Zap escapes, and only in its own panel.

| | **Zap** | **Jetty** | **Top Drawer** |
|---|---|---|---|
| Override scope | the **app** | the **dock item** | the **drawer item** (or the tab, for live listings) |
| Key | `IconIdentity` — bundle path, falling back to bundle ID | `DockItem.id` | `DrawerItem.id`, or the item's path in `Tab.iconStyles` |
| Stored as | PNG copied into `~/Library/Application Support/Zap/Icons/`, indexed by `manifest.json` | a **path string** in `dock.json` | a **security-scoped bookmark** in `launcher.json` |
| Ingestion | `IconImport` — sniffs bytes, rasterises SVG, validates, bounds, re-encodes to PNG | `NSImage(contentsOfFile:)` | `NSImage(contentsOf:)` on the resolved bookmark |
| Generated icons | — | — | ✅ `IconStyle`: folder / rounded tile + colour + SF Symbol |
| Bundle-artwork recovery (un-jailing) | ✅ `BundleArtwork` + `IconShapeClassifier` | — | — |
| Icon themes | ✅ Papirus, Numix, Tela, Breeze, Adwaita | — | — |
| Icon search | ✅ Iconify, keyless | — | — |
| Layout normalisation | ✅ trim / equal-ink scale / bleed / baked shadow | — | — |
| Caching | `IconResolver` — generation-counted, off the main thread, pre-rendered at display size | `LRUImageCacheByKey`, 256 entries, 5-minute TTL | resolved per drawer open, `.task`-deferred |
| Where the code lives | `Zap/Icons/` — 28 files, ~4,400 lines | `DockModel.icon(for:)` — ~12 lines | `ItemView.resolveIcon` — ~50 lines |

Three observations fall out of that table.

**Zap's icon subsystem is the only one that exists.** Jetty and Top Drawer have an
override *field*; Zap has a pipeline. Everything the other two lack — un-jailing,
SVG, themes, search, validation, equal-ink normalisation — is already written and
tested in this repository. Whatever "sharing" means, most of the work is moving code
out of Zap rather than writing anything new.

**The three storage strategies are not equally good, and the gap is not cosmetic.**
Zap copies and re-encodes the user's file, so the original can be moved or deleted
and the icon survives; Top Drawer's bookmark survives a move but not a delete;
Jetty's raw path survives neither. Jetty also decodes whatever the user picked with
no size, format or decompression-bomb check — `IconImageValidator` exists precisely
because that is an in-process parse of untrusted data in an app running under the
hardened runtime (`UNJAILED.md §6.4`).

**The scopes genuinely differ, and that is a feature.** Zap overrides an *app*.
Jetty and Top Drawer override an *item* — and two tiles pointing at the same app can
deliberately carry different icons. That difference has to survive any sharing
scheme, which rules out "one store, one meaning" and points at a layered one (§6.4).

There is also a naming collision waiting: both Zap and Top Drawer have a type called
`IconRenderer`, doing entirely unrelated jobs (bitmap resampling vs. drawing a
coloured folder with a glyph on it).

---

## 3. "Shared" means three separable things

Conflating these is the main way this design goes wrong, so they are named up front:

1. **Shared code.** All three run the same resolution, ingestion and rendering
   logic. Fixing an SVG bug fixes it everywhere. *Does not by itself make one
   user's icon choice visible in another app.*
2. **Shared state.** One icon choice, stored once, read by all three. This is what
   the question actually asks for.
3. **Shared with the system.** The change also applies in the Dock, Finder,
   open/save panels — everywhere. A superset of (2), by a completely different
   mechanism, with a completely different cost profile.

They are independent. You can have (1) without (2) — three apps with identical code
and separate stores. You can have (2) without (1) — a documented file format each
app implements itself. (3) delivers (2) for free and needs neither.

The recommendation in §5 takes (1) and (2) now and (3) as an explicit opt-in later.

---

## 4. The mechanisms, evaluated

### 4.1 Option A — write the icon into the system

macOS has a shared icon-override database already: the one Finder's **Get Info**
panel writes to. Assign an icon there and every app that asks
`NSWorkspace.icon(forFile:)` gets it back — which is all three of ours, plus the
Dock, Finder and every open/save panel. Zero integration work; it already happens.

**And on Tahoe it un-jails.** The community finding is consistent across sources:
macOS masks the artwork an app *ships*, but honours a **user-assigned** icon at its
original shape ([Simon B. Støvring][simonbs], [heise][heise], [9to5Mac][9to5]).
Re-assigning an app's *own* `.icns` through Get Info is enough — the act of
assignment is what earns the exemption. *(Confidence: medium-high. Widely reported,
never verified here.)*

**The mechanics matter, and `UNJAILED.md` gets one detail wrong.** §11.1 rejects
this route partly because it "leaves `com.apple.FinderInfo` / resource-fork detritus,
which is precisely the … `codesign` failure", citing an Apple forums thread. That
thread ([126175][seticon]) is about a spurious *"Invalid image size"* log from
`setIcon(_:forFile:options:)` and says nothing about code signing. The real picture:

- For a **directory** — and an `.app` bundle is one — the icon goes into a hidden
  file named `Icon\r` created at the **top level of the bundle, alongside
  `Contents/`**, plus a `kHasCustomIcon` bit in the `com.apple.FinderInfo` extended
  attribute on the bundle itself ([Eclectic Light][el-icons], [fileicon][fileicon]).
- A bundle's code signature seals `Contents/`, and its hashes cover **data forks
  only, not extended attributes**. So a custom icon applied this way lands outside
  the seal and **does not invalidate the signature** ([Eclectic Light][el-sig]).
- The `codesign` "resource fork, Finder information, or similar detritus not
  allowed" error is real but is about *building* — extended attributes on files
  **inside** the bundle at signing time ([QA1940][qa1940]). It is not what this
  route produces.

So the strongest stated objection to Option A does not hold. The remaining ones do:

| Cost | Severity |
|---|---|
| It mutates other apps' bundles. A cosmetic preference writing into `/Applications` is a different kind of act from drawing a different picture. | **Design principle.** `UNJAILED.md §1.1` treats read-only substitution as the feature's central property. |
| SIP blocks writes to `/System/Applications`, so Safari, Mail, Finder and friends are out — and those are exactly the apps a de-jailer is wanted for. | **High.** Zap's read-only route handles them today. |
| App Store apps are reported not to accept it ([SquircleNoMore][sqnm], [Pictogram][picto]). | Medium. *Unverified — the mechanism above suggests it should work; both tools say it doesn't.* |
| Reverts when an app updates (an updater replacing the bundle drops a root-level `Icon\r`). Needs re-application, i.e. a daemon. Pictogram ships exactly that. | **High.** |
| Needs write permission to `/Applications`; may prompt for admin. | Medium. |
| Loses Zap's per-app disambiguation. `IconIdentity` exists because SSB wrappers share one bundle ID; the filesystem doesn't have that problem, but the *undo* story becomes "what was there before", which nobody stored. | Medium. |
| Undo means remembering the previous state for apps that may since have been deleted. | Medium. |

**Verdict: not the primary mechanism, but a genuinely good *second* action.** It is
the only route that reaches Finder and the Dock, it is signature-safe, and — this is
the part worth noticing — a shared store (Option B) is precisely what makes its
re-application problem tractable. If you always know what icon the user chose for an
app, re-applying after an update is a loop over the store, not a database you have
to invent. B and A compose; A alone does not cover system apps.

### 4.2 Option B — a shared store on disk

A directory in `~/Library/Application Support/`, outside any one app's folder, that
all three read and write.

- All three apps are **unsandboxed** (Zap and Top Drawer carry only
  `com.apple.security.automation.apple-events`; Jetty's entitlements file says so in
  a comment), so there is no container to escape and no bookmark to negotiate.
- `~/Library/Application Support` is not TCC-protected, so no permission prompt.
- Nothing needs signing, entitlements, a Team ID, or a helper process.
- The format is ours, so it can carry exactly what the three apps need — provenance,
  licence and credit included, which `UNJAILED.md §5.4` makes a hard requirement.

Costs: an on-disk contract between three **independently released** apps (§8), a
multi-writer story (§6.3), and a shared directory that outlives any one app's
uninstall.

**Verdict: the primary mechanism.** Everything the question asks for, nothing that
needs infrastructure these apps don't have.

### 4.3 Option C — an App Group container

The Apple-sanctioned way to share state between apps from one vendor:
`~/Library/Group Containers/<group>`, reachable via
`containerURL(forSecurityApplicationGroupIdentifier:)`.

**Ruled out.** On macOS the group identifier must be prefixed with the developer's
**Team ID**, or the claim must be backed by a provisioning profile, or the app must
come from the App Store or TestFlight — otherwise the system prompts the user for
access ([Apple][appgroups], [entitlement reference][entitlements]). All three apps
here ship **unsigned and ad-hoc-codesigned** (`CICD.md`: "not a Developer ID
signature and the app is not notarized"), with no `DEVELOPMENT_TEAM` in any project
file. There is no Team ID to prefix with.

It would also buy nothing over Option B. Group containers exist to punch through the
sandbox; there is no sandbox here.

*Revisit only if these apps ever move to Developer ID + notarisation — and even then
the answer is "same design, different directory".*

### 4.4 Option D — an interchange format, no shared state

Ship `UNJAILED.md`'s unbuilt phase 5 (`.zapicons` packs) in all three apps: export
from one, import into another.

Cheap, needs no coordination, no live contract, no watcher. And it does not answer
the question — it makes the change *transferable*, not *shared*. Every change is
still made three times, or made once and re-exported.

**Verdict: a useful thing to build anyway** (it is how a user backs up or moves their
icons, and how they share them with someone else), but not an answer.

### 4.5 Option E — a helper process

A login-item daemon or XPC service that owns the icons and vends them.

The only thing it adds over a plain directory is coordinated writes and push
notification — both of which §6.3 and §6.5 get for free from atomic per-entry files
and FSEvents. Against that: a fourth process, a launch-agent registration, an
IPC protocol, three clients that have to survive it not running, and a much worse
story when only one of the three apps is installed.

**Verdict: rejected.** It solves problems the file system already solved.

### 4.6 Option F — do nothing

Worth stating plainly, because the recommendation has real costs. Today each app is
independently releasable with no cross-repo contract. Sharing means a fourth
repository, version coordination across three release cadences, and an on-disk
format that an old build has to tolerate a newer build writing.

The case against F is that the duplication is already there and already uneven:
Jetty's icon ingestion has no validation Zap spent a phase building, and neither
Jetty nor Top Drawer un-jails anything, in an OS release where that is the actual
complaint. F means writing Zap's pipeline twice more, or shipping two apps that are
worse at icons than the third for no reason.

---

## 5. Recommendation

**Do (1) and (2) from §3 together, as one shared Swift package plus one shared store,
and treat (3) as a later opt-in built on top of them.**

```
                     ┌───────────────────────────────────────────┐
   Zap  ────────────►│  IconKit (SwiftPM package)                │
   Jetty ───────────►│  resolution · ingestion · rendering ·     │
   Top Drawer ──────►│  themes · search · the shared store API   │
                     └────────────────────┬──────────────────────┘
                                          │
                     ~/Library/Application Support/<Shared>/Icons/
                                          │
                        (optional, opt-in) ▼
                     Icon\r + FinderInfo → Dock, Finder, everywhere
```

Concretely:

1. **Extract `Zap/Icons/` into a package** the three apps depend on. No behaviour
   change to Zap; Jetty and Top Drawer gain un-jailing, validated ingestion, SVG,
   themes and search by consuming it.
2. **Move the store out of `Zap/Icons` into a shared directory**, re-keyed so it can
   name any target the three apps draw (apps, files, folders, links), and re-shaped
   for three concurrent writers.
3. **Layer it, don't replace.** Jetty's and Top Drawer's per-item overrides keep
   winning; the shared store is a new rung beneath them and above bundle-artwork
   recovery. Nobody's existing icons change.
4. **Two verbs in the UI**, because there are two different intents (§6.6).
5. **Later, optionally:** an explicit "Also apply in Finder and the Dock" action that
   pushes an entry out through the `Icon\r` route, with re-application after app
   updates — reachable precisely because the store knows what was intended.

---

## 6. The design

### 6.1 Where it lives

```
~/Library/Application Support/<Shared>/
  README.txt            what this is, which apps write it, how to delete it
  Icons/
    entries/
      com.apple.Safari-1k2j4h.json
      com.apple.Safari-1k2j4h.png
      _Applications_Claude__-9zx1qp.json
      _Applications_Claude__-9zx1qp.png
  IconSets/
    papirus/ …          the themes, installed once instead of three times
```

**`<Shared>` needs a name, and there is no obvious one.** The three bundle
identifiers are `com.zapapp.Zap`, `com.jettyapp.Jetty` and `com.macdring.MacDring` —
three unrelated reverse-DNS roots, no common prefix to inherit. A shared identifier
has to be invented. Candidates: `Unjailed` (matches the feature's existing name in
this repo and says what it is), `L-K-M` (matches the GitHub org), or a fourth
reverse-DNS root. Left open in §9 — it is a product decision, and it is permanent
once shipped.

Sharing `IconSets/` is close to free and worth taking: Papirus alone is ~4 MB
extracted, and three apps that each install it three times is 12 MB and three 31 MB
downloads for one theme.

### 6.2 What a key is

Zap keys on `IconIdentity` — the standardised bundle path, falling back to the bundle
identifier for entries written before that change. Jetty and Top Drawer hold URLs and
bookmarks, and their items can be files, folders and links as well as apps. So the
key generalises to a discriminated pair rather than a bare string:

| Kind | Value | Written by |
|---|---|---|
| `app` | the app bundle's standardised path | Zap, and any app-kind item elsewhere |
| `bundleID` | the bundle identifier | fallback only — see below |
| `file` | a standardised file or folder path | Jetty, Top Drawer |
| `url` | a normalised `https://…` | Top Drawer's link items |

Serialised as `app:/Applications/Safari.app`. Lookup for an application tries
`app:` then `bundleID:`, which is exactly `IconIdentity.lookupKeys` generalised — and
it preserves the reason that ladder exists: site-specific-browser wrappers all report
one identifier, so path-first is what keeps three Chrome wrappers from sharing one
icon (`IconIdentity`'s header documents the case).

`bundleID:` stays *writable* for one thing Zap can't currently express: "this app
wherever it lives", which is the right key for an app the user moves between
`/Applications` and `~/Applications`. Path-first lookup means it never overrides a
path entry, so it is a safe addition rather than a re-litigation of that decision.

### 6.3 One file per entry, not one manifest

`manifest.json` is a single-writer design. Three processes read-modify-writing it
will lose entries: Zap reads it, Jetty writes it, Zap writes its stale copy back.
`NSFileCoordinator` would fix that and adds a coordination protocol to every read on
a path that must stay cheap.

**Splitting the manifest into one JSON per entry removes the problem instead of
managing it.** Two apps overriding two different apps' icons touch two different
files and cannot conflict at all. Two apps overriding the *same* app's icon resolve
by last-writer-wins, which is the correct semantics for "the user set this icon" and
needs no lock to be right. Each write is `Data.write(options: .atomic)` — a temp file
and a rename, so no reader ever sees half a file. The directory listing *is* the
index; there is no index to keep in step.

The file name is `IconManifest.fileName(forBundleID:)`'s scheme applied
unconditionally: a sanitised stem plus a short FNV-1a digest of the full key. That
code already exists, is already tested for path-traversal, and already solves the
"two keys sanitise to one name" collision. Making the digest unconditional (rather
than only when sanitising changed something) keeps names uniform and inspectable.

An entry carries what the current `IconManifest.Entry` carries — `source`,
`provider`, `credit`, `creditURL`, `licence`, `addedAt` — plus its own `key`
verbatim, so the index can be rebuilt from the files alone, and `writtenBy` (which
app made the change), which costs nothing and makes the directory self-explaining.

Validation stays as strict as `IconManifest.validated()` is today, for the same
reason: an entry can arrive in an imported pack or be hand-edited, so file names are
bounds-checked against the directory and every number is clamped. A JSON whose PNG is
missing — the state a half-finished delete leaves — simply fails validation and the
resolver falls through to the next rung.

Scale: one entry per overridden target, so tens to low hundreds. Listing a directory
that size on load and on change is not a cost worth optimising.

### 6.4 Precedence

The rule is that **a per-item choice always beats a shared one**, because a per-item
choice is more specific and was made more deliberately.

**Jetty / Top Drawer**, per item:

```
1. the item's own override        ← existing behaviour, unchanged
     (customIconPath / customIconBookmark / iconStyle)
2. the shared store               ← new
3. the target's own bundle artwork, un-jailed  ← new (Zap's Level 2)
4. NSWorkspace.icon(forFile:)     ← today's default
```

**Zap**, per app: rung 1 doesn't exist (there is no per-item layer in a switcher), so
its ladder is unchanged from `UNJAILED.md §3` — the store it consults is just the
shared one now.

Two consequences worth stating:

- **Nobody's icons change on upgrade.** Every existing per-item override stays at the
  top of its ladder. The shared store starts empty in Jetty and Top Drawer and only
  fills as the user uses it.
- **Rung 3 is a visible change** — pinned apps in Jetty's dock stop being
  squircle-plated. That is the whole point in Zap, and a product decision in Jetty,
  which *replaces the Dock* and may be expected to match it. See §9.

### 6.5 Noticing a change

FSEvents on `Icons/entries/`, with `kFSEventStreamCreateFlagFileEvents` and a short
latency. On an event each app re-lists the directory and invalidates its cache —
`IconResolver.invalidate()` in Zap (which already exists and is already generation-
counted for exactly this), the LRU in Jetty, nothing in Top Drawer, which resolves
per drawer open anyway.

FSEvents rather than `DispatchSource.makeFileSystemObjectSource` because a directory
watch via a file descriptor needs manual re-arming across renames, and every write
here is a rename. No permission is involved for an unsandboxed app reading its own
Application Support.

A `DistributedNotificationCenter` post on write would make the update feel instant
rather than sub-second, and is about five lines ([Apple][dnc]). Worth having as a
*hint*, never as the mechanism — a distributed notification is ephemeral, and an app
that was launching when it fired never sees it. The file watch is the source of
truth; the notification only shortens the latency.

### 6.6 Two verbs

Sharing introduces an ambiguity that has to be resolved in the UI, not in the model.
When a user right-clicks a Safari tile in Jetty and picks "change icon", they might
mean *this tile* or *Safari*. Both are legitimate; Jetty and Top Drawer already mean
the first, and the second is the new thing.

So: two menu items, named for their scope.

```
Customise This Item's Icon…        → per-item, existing behaviour
Change Safari's Icon Everywhere…   → the shared store
```

And when an icon comes from the shared store, the row says so and names the other
apps it affects. A change with reach the user didn't ask for is the failure mode this
whole design has to avoid, and the fix is that the reach is written on the button.

Zap's Icons tab is inherently the second verb — every override it makes is an app's,
not a row's — so its UI is unchanged except for a note that the change reaches the
other installed apps.

### 6.7 What goes in the package, and what doesn't

Straight across, essentially unmodified:

```
IconStore              re-shaped for §6.3's entry-per-file
IconManifest → IconEntry + IconEntryKey (§6.2)
IconImageValidator     the §6.4 decode bounds
IconImport             the single ingestion door
SVGRasterizer          offscreen WKWebView, CSP, JS off
SVGRenderGate          concurrency ceiling on rasterisation
IconRenderCache        content-addressed, renderVersion-keyed
BundleArtwork          Level 2 — the un-jailing itself
IconShapeClassifier    + AlphaMask
IconNormalizer         trim / equal-ink scale / bleed / shadow
IconRenderer → IconBitmap   renamed: Top Drawer already has an IconRenderer
Sets/*                 IconSet, catalogue, installer, library, name guess, auto-match
Search/*               provider protocol, Iconify client, collection cache
```

The module is unusually clean to extract — `import CoreGraphics` and
`import Foundation` almost throughout, with AppKit only in `BundleArtwork`,
`IconResolver` and `SVGRasterizer`, and exactly two ties to the rest of Zap:
`IconResolver.init(preferences:)` and `IconNormalizer`'s reference to
`IconRowMetrics.maximumBleed`. That is a seam, not a knot.

**`IconResolver` splits.** The package ships the caching, generation counting and
resolution ladder, parameterised by a plain value struct — source mode, target pixel
size, bleed, trim, shadow. Each app keeps the code that maps *its* preferences onto
that struct: Zap's Combine subscriptions and `NSScreen` backing-scale tracking stay in
Zap, because they are about Zap's Appearance tab and Zap's icon-size slider. Jetty
would wire far less, and Top Drawer less again.

**Top Drawer's `IconStyle` and generated icons stay in Top Drawer** for now. They are
a different feature — synthesising an icon rather than substituting one — and only
one app has them. Promoting them later is a small move if Jetty ever wants them.

### 6.8 How three Xcode projects consume it

| | Pro | Con |
|---|---|---|
| **A new public repo + SwiftPM remote package**, tagged and pinned | Ordinary dependency resolution; each app upgrades on its own schedule; CI resolves it anonymously | A fourth repo; landing one change means a tag plus three bumps |
| Git submodule + local package reference | No tag dance | Submodule friction in every clone and in CI (`submodules: recursive`); pinning by commit is a version scheme with no names |
| Vendored copy, synced by a script | Cheapest to start | Three copies that drift, which is the problem restated |

**Recommend the remote package.** It is the only one where "which version of the
icon code is this build running" has an answer.

Two notes on the ground here. `AGENTS.md` says "don't add heavy dependencies; prefer
system frameworks" — a first-party package under the same org, containing code that
is *already in this repository*, is not what that rule is about, but the rule should
be amended to say so rather than quietly bent. And all three CI workflows pin
`macos-14` / Xcode 16.2 and build with `CODE_SIGNING_ALLOWED=NO`; package resolution
works there, and caching `-clonedSourcePackagesDirPath` between runs is a small,
optional win.

### 6.9 Migration

Zap has shipped `~/Library/Application Support/Zap/Icons/manifest.json` since phase 1,
so there are real user icons to carry across. A one-time importer on first launch of
the new build: read the old manifest, write one entry per row into the shared store
(`storageKey` maps to `app:` when it is a path and `bundleID:` when it isn't — the
`IconIdentity.isPath(_:)` test that already exists), copy the PNGs, then rename the
old directory to `Icons.migrated-<date>` and leave it for one release.

Not a symlink: two writers and one inode is exactly the ambiguity §6.3 removes.

Jetty and Top Drawer need no migration. Their overrides stay where they are, at the
top of the ladder.

---

## 7. Phasing

| Phase | Scope | Ships |
|---|---|---|
| **0** | Extract `Zap/Icons/` into the package; Zap builds against it. Store, keys and behaviour untouched. | Nothing user-visible. The riskiest mechanical step, taken alone and verifiable by "Zap behaves identically". |
| **1** | Shared store: new location, `IconEntryKey`, entry-per-file, FSEvents, migration. Zap only. | Still one app, but the format and the contract are real and exercised. |
| **2** | Jetty consumes the package: shared store as rung 2, bundle-artwork un-jailing as rung 3, validated ingestion replacing `NSImage(contentsOfFile:)`. Read-only at first. | **The first time a Zap change shows up in another app.** |
| **3** | Top Drawer the same. | All three read one store. |
| **4** | The write path in Jetty and Top Drawer — "Change this app's icon everywhere", the picker, the search sheet, the theme picker. | One change, made anywhere, applied everywhere. The question, answered. |
| **5** | Interchange packs (`UNJAILED.md` phase 5), now shared-store-shaped. | Backup, transfer, sharing between people. |
| **6** | Opt-in system-wide application via `Icon\r` + re-application after app updates. | The Dock and Finder too — for the apps SIP allows. |

Phases 0–2 are the ones that carry the risk and most of the value. 4 is where it
starts to feel like one feature. 6 is a different product decision and should not be
bundled with the rest.

---

## 8. Costs, honestly

**An on-disk format shared by independently-released apps is a compatibility
contract.** A user can run Zap 4.0 and Jetty 1.4 against one directory. The rules
that make that survivable: entries carry a `version`; a reader skips entries it
doesn't understand rather than failing the load; a writer **never rewrites an entry it
didn't fully parse** (which is how a fourth field gets silently dropped by an old
build). This is the same discipline `DockStore` already applies to `dock.json` when
it finds a newer version — it goes read-only for the session and says so in the log.
That precedent should be copied, not reinvented.

**Three release cadences.** A package fix reaches users only as fast as the slowest
of three releases. Nothing to be done about it beyond noticing that it argues for
keeping the package's surface small and its behaviour boring.

**A shared directory outlives the apps.** Delete all three and it stays. A `README.txt`
naming it and saying it is safe to delete is the whole mitigation, and it is worth the
five minutes.

**Rung 3 changes how Jetty and Top Drawer look**, by design and on upgrade. It should
be a preference in both, and `IconSourceMode.systemDefault`'s reasoning ("only on where
it does something") transfers — but whether Jetty, a Dock *replacement*, should default
to not matching the Dock is a genuine product call and not one this document should
make.

**Zap's read-only property.** `UNJAILED.md §1.1` makes "Zap writes nothing into any
bundle" a headline claim, and phase 6 would end that. It should therefore be opt-in,
per-app, clearly labelled, and — this matters — it should stay a *separate action*
from setting an icon in the store, not a checkbox that silently changes what "change
this icon" does.

---

## 9. Open questions

1. **What is `<Shared>` called?** No common prefix exists among the three bundle IDs
   (§6.1). Permanent once shipped.
2. **Does `NSWorkspace.icon(forFile:)` return a user-assigned custom icon *unmasked*
   on Tahoe?** Load-bearing for Option A and for phase 6, reported consistently by
   three independent sources, verified here by none. Ten minutes on a Tahoe machine.
3. **Do App Store apps really refuse the `Icon\r` write?** Two tools say so
   ([SquircleNoMore][sqnm], [Pictogram][picto]); the mechanism in §4.1 suggests they
   shouldn't. Someone should try it.
4. **Should Jetty un-jail by default?** It replaces the Dock; matching the Dock is a
   defensible default and so is fixing it.
5. **Should the shared store also hold the themes?** §6.1 says yes on disk-space
   grounds. It also means one app's theme update is visible to the others mid-session,
   which the installer's `If-None-Match` flow was not written for.
6. **Is a fourth app the real answer?** A tiny "Icons" preference pane owning the
   store, with the three apps as pure readers, is a cleaner separation and a much
   worse install story for someone who only wants Zap. Recommended against, but it is
   the road not taken and deserves recording.
7. **Should `bundleID:` entries be user-creatable** ("this app wherever it lives",
   §6.2), or only exist as legacy fallbacks? Adding a second way to key one app is a
   second way to be confused about which one applied.

---

## Sources

- [How To Bring Back Oddly Shaped App Icons in macOS 26 Tahoe — Simon B. Støvring][simonbs]
- [Icons in macOS 26: Fighting the "Squircle" Prison — heise][heise]
- [macOS Tahoe put your apps in icon jail? Here's the fix — 9to5Mac][9to5]
- [Apple Should Eliminate the App Icon 'Squircle Jail' — Daring Fireball][df]
- [First Look: macOS Golden Gate Public Beta — Six Colors][sixcolors] (macOS 27 keeps the mask; no opt-out)
- [Custom Finder icons, resources and Mac OS history — The Eclectic Light Company][el-icons]
- [How to add a custom icon to an app without breaking its signature — The Eclectic Light Company][el-sig]
- [fileicon — how custom icons are stored (`Icon\r`, `com.apple.FinderInfo`)][fileicon]
- [Technical Q&A QA1940 — "resource fork, Finder information, or similar detritus not allowed"][qa1940]
- [`setIcon(_:forFile:options:)` — Apple Developer Documentation][setIcon] · [forum thread 126175][seticon] (cited in `UNJAILED.md §11.1`; does **not** support the claim made there)
- [Accessing app group containers in your existing macOS app — Apple][appgroups] · [Entitlement Key Reference][entitlements]
- [`DistributedNotificationCenter` — Apple Developer Documentation][dnc]
- [SquircleNoMore — Tweaking4All][sqnm] · [Pictogram][picto]

[simonbs]: https://simonbs.dev/posts/how-to-bring-back-oddly-shaped-app-icons-on-macos-26-tahoe/
[heise]: https://www.heise.de/en/news/Icons-in-macOS-26-Fighting-the-Squircle-Prison-11075561.html
[9to5]: https://9to5mac.com/2025/08/08/macos-tahoe-fix-gray-box-icons/
[df]: https://daringfireball.net/2026/07/eliminate_app_icon_squircle_jail
[sixcolors]: https://sixcolors.com/post/2026/07/first-look-macos-golden-gate-public-beta/
[el-icons]: https://eclecticlight.co/2023/03/04/custom-finder-icons-resources-and-mac-os-history/
[el-sig]: https://eclecticlight.co/2019/07/20/how-to-add-a-custom-icon-to-an-app-without-breaking-its-signature/
[fileicon]: https://github.com/mklement0/fileicon
[qa1940]: https://developer.apple.com/library/archive/qa/qa1940/_index.html
[setIcon]: https://developer.apple.com/documentation/appkit/nsworkspace/seticon(_:forfile:options:)
[seticon]: https://developer.apple.com/forums/thread/126175
[appgroups]: https://developer.apple.com/documentation/xcode/accessing-app-group-containers
[entitlements]: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html
[dnc]: https://developer.apple.com/documentation/foundation/distributednotificationcenter
[sqnm]: https://www.tweaking4all.com/software/macosx-software/squirclenomore-getting-rid-of-the-ugly-macos-tahoe-icons-jail/
[picto]: https://pictogramapp.com/
