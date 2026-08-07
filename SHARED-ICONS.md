# SHARED-ICONS — one icon change, three apps

*A research study, August 2026, now partly built. This document asks whether Zap,
Jetty and Top Drawer can share a single way to change an app's icon, concludes that
they can, works out which of the five available mechanisms is the right one, and
records what it costs.*

**Where this stands.** §1–§4 are the survey and are unchanged. §5 onward is the
decision, revised once: the shared store now lives in a fourth app,
[**Pict**](https://github.com/L-K-M/Pict), which owns every part of *changing* an
icon while Zap, Jetty and Top Drawer become readers. `PictKit` — the store and the
read path — is written and pushed. Nothing else is built, and Zap is unchanged and
still works exactly as it does today. §7 has the sequence.

**Verification caveat** (inherited from `UNJAILED.md` and `ANALYSIS.md`): written
without a macOS toolchain or a Tahoe machine, so `PictKit` has never been through a
compiler and none of its tests have run. Claims about system behaviour carry
confidence markers; the load-bearing ones are collected in §9.

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

**A fourth app — [Pict](https://github.com/L-K-M/Pict) — owns the shared store and
every part of changing an icon. The three existing apps become readers.**

That is a stronger version of the obvious answer, and it was reached by pricing the
objection to it rather than by assuming it away. §4.2's shared store is still the
mechanism; the question this section answers is *where the code that fills it lives*.

```
                     ┌──────────────────────────────────────┐
   Zap  ────────────►│  PictKit — the read path             │
   Jetty ───────────►│  store · artwork recovery ·          │
   Top Drawer ──────►│  classification · normalisation      │
        │            └──────────────────┬───────────────────┘
        │                               │
        │      ~/Library/Application Support/Pict/entries/
        │                               │
        │            ┌──────────────────┴───────────────────┐
        └───────────►│  Pict.app — everything that WRITES   │
        "Customise   │  ingestion · SVG · themes · search · │
         in Pict…"   │  the editing UI                      │
                     └──────────────────────────────────────┘
```

### 5.1 What this costs, stated first

**A Zap-only user cannot pick a custom icon file.** That is a real regression and
the reason to think hard before taking this. It is also much smaller than it sounds:

- **Level 2 un-jailing still works with no editor installed.** Reading the bundle,
  classifying the alpha and substituting needs no user action and no UI. It runs for
  every app, automatically. `UNJAILED.md §10` says it outright — *"Phase 1 stands
  alone and is worth shipping alone… Everything after it is optional polish on a
  problem already solved for the majority of apps."*
- **Pin-to-system still works**, because it writes an entry with no image and touches
  no ingestion code at all.
- What a Zap-only user loses is *Choose File…*, drag-and-drop, search and themes —
  which is precisely phases 2–4 of that same document.

So the trade is: Zap keeps the part `UNJAILED.md` calls the whole point, and sheds
the parts it calls optional. Plus a fourth unsigned download with its own Gatekeeper
right-click→Open ritual for anyone who wants those back.

### 5.2 What it buys

**Zap loses 43% of its code and 49% of its tests.**

| | lines | share |
|---|---|---|
| Zap app code | 13,421 | |
| …icon subsystem | **5,718** | **43%** |
| ZapTests | 6,340 | |
| …icon tests | **3,090** | **49%** |

Split at the read/write line, roughly **3,800 lines of app code leave Zap**, plus
the tests that go with them. What stays is about 1,900 lines: the resolution ladder
and the store, which is the only part the ⌘-Tab path has ever touched.

**What leaves is disproportionately the dangerous part**, and this is the real
argument:

- Zap's **only** `import WebKit`. No `WKWebView` in a process holding Accessibility
  permission.
- **Every** icon-related network call — `IconifyClient`, `RemoteIconFetcher`,
  `IconSetInstaller`, `CollectionCache`, `IconSetLibrary`. What remains in Zap is the
  update checker.
- Zap's **only** subprocess spawn (`tar`, in `IconSetInstaller`, which says so in its
  own header).
- **All** ingestion of untrusted images.

That last one closes a gap `UNJAILED.md` left open. §6.4: *"The thorough fix is
decoding inside a short-lived XPC service that can be sandboxed to nothing. That is
the right answer eventually and too much for v1."* A separate editor **is** that fix,
reached by an app boundary instead of an XPC service — and unlike Zap, an icon editor
needs no Accessibility, no event tap and no window list, so it is the only one of the
four that could ever be sandboxed.

**It also collapses two phases of the integration.** Jetty and Top Drawer do not port
an editor. They add one rung to their icon ladder and one menu item that opens a
URL — on the order of 100 lines each.

### 5.3 What was rejected on the way here

**Shipping the editor as a shared SwiftUI view in the package**, so each app could
edit inline and Pict was merely a convenience shell. It resolves the install-story
objection and it is the wrong trade: it puts ingestion, SVG rasterisation and theme
downloads back into every app that links the package, which is the entire cost §5.2
is trying to shed. If the editor is a library, Zap carries the `WKWebView` again.

**Bundling Pict inside each app** at `Contents/Library/`. Avoids the extra download
and gives three copies that can race on version — the drift the shared package
exists to kill.

---

## 6. The design, as built

`PictKit` and the store are written and pushed;
[`L-K-M/Pict`](https://github.com/L-K-M/Pict) has the code and `PLAN.md` has the
decisions in full. What follows is the shape and the reasoning, not a duplicate.

### 6.1 Where it lives

```
~/Library/Application Support/Pict/
  README.txt
  entries/
    Safari.app-1k2j4h.json
    Safari.app-1k2j4h.png
```

The name is **Pict**. There was no prefix to inherit — the three bundle identifiers
(`com.zapapp.Zap`, `com.jettyapp.Jetty`, `com.macdring.MacDring`) share no
reverse-DNS root — so a neutral one had to be invented rather than putting a shared
store inside one app's folder.

The `README.txt` is not decoration. A shared directory outlives every app that writes
it: delete all four and it stays. Someone will open it wondering what put PNGs in
their Library, and a file that answers them, and says deleting it is safe, is the
entire mitigation.

### 6.2 One file per entry, not one manifest

The single most consequential change from Zap's design.

`manifest.json` is single-writer. Three processes read-modify-writing it *will* lose
entries: Zap reads it, Pict writes it, Zap writes its stale copy back.
`NSFileCoordinator` would fix that and would add a coordination protocol to every
read on a path that has to stay cheap.

Splitting it removes the problem rather than managing it:

- Two apps overriding two different targets touch two different files and **cannot
  conflict at all**.
- Two apps overriding the same target resolve by last-writer-wins, which is the
  correct semantics for "the user set this icon" and needs no lock to be right.
- Every write is `Data.write(options: .atomic)` — temp file plus rename — so no
  reader in another process ever sees a partial file.
- **The directory listing is the index.** There is no index to keep in step.

A half-finished delete leaves a JSON whose PNG is gone; that fails validation and the
resolver falls through to the next rung, which is exactly right.

File names are a sanitised stem plus an **unconditional** FNV-1a digest of the whole
key. Zap appended the digest only when sanitising had changed something, which kept
the common case readable at the cost of two naming rules; with four key kinds sharing
one directory, uniform names are worth more. Never `hashValue`, which Swift seeds per
process — that would name one target's files differently in each of the four apps.

### 6.3 Keys

Zap keyed on a bundle path with an identifier fallback, which suits an app that only
ever draws applications. The key generalises to a discriminated pair — `app`,
`bundleID`, `file`, `url` — serialised as `app:/Applications/Safari.app`.

Path-before-identifier is preserved and is load-bearing: site-specific-browser
wrappers ship one bundle per site and all report the browser's identifier, so an
identifier-first ladder paints every wrapper with one icon. Writing the path key
retires the identifier key, or a stale entry resurfaces the day the app moves.

### 6.4 Precedence

**Jetty / Top Drawer**, per item:

```
1. the item's own override        ← existing behaviour, unchanged
2. the shared store               ← new
3. the target's own bundle artwork, un-jailed  ← new
4. NSWorkspace.icon(forFile:)     ← today's default
```

A per-item choice always beats a shared one: it is more specific, it was made more
deliberately, and two dock tiles pointing at one app are allowed to differ. **Nobody's
existing icons change on upgrade** — the shared store starts empty in both apps.

Rung 3 *is* a visible change: pinned apps stop being squircle-plated. That is the
point in Zap and a product decision in Jetty, which replaces the Dock and might
reasonably be expected to match it (§9).

**Which rungs are live is not a shared setting.** Zap has an icon-source preference —
a switcher row the user can put back to plain system icons — and it selects how far
down this ladder to go. Jetty and Top Drawer have no such preference, and must not
inherit Zap's default: on anything before macOS 26 that default is "system icons",
which switches the ladder off entirely, and even its jailed-system value stops at rung
3 and never reads the store. An app with no preference to consult asks for the whole
ladder unconditionally.

This is worth stating because getting it wrong is silent. Nothing errors, nothing logs;
the store is simply never read, and the feature looks implemented from every angle
except the screen. It shipped that way for a day (`IconRenderOptions.plain` inherited
the default), which is why the shortcut now names the mode outright and a test pins it.
An icon the user picked by hand is not a display flourish, and no OS version makes it
stop being their choice.

### 6.5 Noticing a change

FSEvents on the entries directory, with `kFSEventStreamCreateFlagWatchRoot` (the
directory does not exist until someone sets an icon) and `IgnoreSelf` (an app should
not invalidate its cache over its own write).

Not `DispatchSource.makeFileSystemObjectSource`: it watches a file descriptor, and
every write here is a rename, so the descriptor stops being the file that matters.
Watching the directory that way means re-arming by hand on every event and racing the
next one.

FSEvents delivers on its own queue, so the watcher hops to main before calling back.
Every consumer of it touches UI, and making that the watcher's job rather than each
app's means the guarantee is stated in one place instead of assumed in three.

**Noticing is not enough on its own.** Learning the store changed is the easy half; the
hard half is that resolution is asynchronous. Dropping the cache re-renders in the
background, so an app that redraws *at* the moment it hears the news reads a miss and
draws the system icon — and an app that caches what it drew (Jetty's dock does, with a
five-minute TTL) then pins the squircle-masked fallback on screen for five minutes,
starting from the instant the user picked a new icon. The obvious fix is exactly
backwards.

So the resolver has a second signal, fired on the main queue once a re-render has
actually landed artwork, and consumers with a downstream cache redraw on *that*. Both
signals are needed, not either alone:

| | fires | why it can't be dropped |
|---|---|---|
| store changed | on the write | an icon the user *removed* resolves to the system icon and lands no artwork, so the second signal never comes |
| artwork resolved | when the bitmap exists | the first signal alone redraws into an empty cache |

The same pair carries a display change: a sharper screen re-renders everything, and the
dock is told when it can read the new bitmaps rather than when the old ones were
dropped.

### 6.6 Two verbs

Sharing introduces an ambiguity that has to be resolved in the UI, not the model.
Right-clicking a Safari tile in Jetty could mean *this tile* or *Safari*.

```
Customise This Item's Icon…     → per-item, existing behaviour, stays local
Change Safari's Icon Everywhere… → opens Pict at that app
```

Discovery without launching: `NSWorkspace.urlForApplication(toOpen:)` on the URL
scheme returns nil when Pict isn't installed, so the menu shows the second item or a
*Get Pict…* line accordingly. No callback is needed — the store change *is* the
notification, via §6.5.

Zap's Icons tab keeps the source-mode picker, the app list and the per-row status
caption (*"Original artwork (free-form)"*, *"Already square — nothing to fix"*), all
of which are read-side. The `⋯` menu keeps *Use original artwork* and *Use system
icon*; its other three items become one **Customise in Pict…** link.

### 6.7 Migration

`ZapManifestImport` runs once, maps each legacy key onto `app:` or `bundleID:` by its
leading slash, copies the PNGs, and **renames** the old directory rather than deleting
it — a user who downgrades still has their icons. Not a symlink: two writers and one
inode is exactly the ambiguity §6.2 removes.

Jetty and Top Drawer need no migration; their overrides stay where they are, at the
top of the ladder.

---

## 7. Phasing

| Phase | Scope | Status |
|---|---|---|
| **0** | `PictKit`: store, keys, resolver, artwork recovery, migration | **written, not compiled** |
| **1** | Zap builds against it; editing code deleted; Icons tab reduced to read-side | not started |
| **2** | Pict app: editor, ingestion, SVG, themes, search, URL scheme | not started |
| **3** | Jetty: one rung, one menu item, un-jailing in the dock | not started |
| **4** | Top Drawer, the same | not started |
| **5** | Interchange packs — backup, transfer, sharing between people | not started |
| **6** | Opt-in system-wide application via `Icon\r`, re-applied after app updates | not started |

Phases 1 and 2 are the ones that carry risk: 1 deletes a great deal of working code,
and 2 has to receive it without losing behaviour. 3 and 4 are small by construction.

**Phase 6 is what makes Pict an app rather than a view.** The system-wide route
reverts whenever an app updates, so it needs something watching `/Applications` and
re-applying — Pictogram ships exactly that daemon. That is real background work, none
of the three utilities should host it, and it needs somewhere to live.

---

## 8. Costs, honestly

**The install regression** (§5.1) — priced and accepted.

**An on-disk format shared by independently released apps is a compatibility
contract.** A user can run Zap 4.0 against Jetty 1.4 and Pict 1.0 over one directory.
The rules that make it survivable are enforced in `IconEntry`/`IconStore`: entries
carry a version, every field is optional, a reader skips what it cannot parse rather
than failing the load, and **a reader never rewrites an entry it does not fully
understand** — which is how a newer build's fields get silently dropped. Jetty's
`DockStore` already applies this discipline to `dock.json`; it was copied, not
reinvented.

**Zap can no longer fix an ingestion bug in its own release.** A broken SVG render or
a theme that changed layout needs a *Pict* release, and old-Pict-plus-new-Zap has to
keep working. This is the same contract, but now load-bearing for a feature rather
than a nicety — which is the argument for keeping the version discipline strict from
the first commit rather than adding it once it hurts.

**Four release cadences.** A `PictKit` fix reaches users as fast as the slowest of
four releases. It argues for keeping the package's surface small and its behaviour
boring, which is what `AGENTS.md` in that repo now says out loud.

**Rung 3 changes how Jetty and Top Drawer look**, by design and on upgrade. It should
be a preference in both.

**Zap's read-only property.** `UNJAILED.md §1.1` makes "Zap writes nothing into any
bundle" a headline claim and phase 6 would end it. Opt-in, per-app, clearly labelled —
and kept a *separate action* from setting an icon, never a checkbox that silently
changes what "change this icon" does.

---

## 9. Open questions

1. ~~What is the shared directory called?~~ **Resolved: `Pict`.**
2. ~~Is a fourth app the real answer?~~ **Resolved: yes** — see §5. The deciding
   argument was not convenience but that it moves every untrusted-input path out of
   the app holding Accessibility permission, and makes that code sandboxable for the
   first time.
3. **Does `NSWorkspace.icon(forFile:)` return a user-assigned custom icon *unmasked*
   on Tahoe?** Load-bearing for §4.1 and phase 6; reported consistently by three
   independent sources, verified here by none. Ten minutes on a Tahoe machine.
4. **Do App Store apps really refuse the `Icon\r` write?** Two tools say so
   ([SquircleNoMore][sqnm], [Pictogram][picto]); the mechanism in §4.1 suggests they
   shouldn't.
5. **Should Jetty un-jail by default?** It replaces the Dock; matching the Dock is a
   defensible default and so is fixing it.
6. **Should the themes move into the shared directory too?** Disk says yes — Papirus
   is ~4 MB extracted and three copies is 12 MB and three 31 MB downloads. But with
   Pict as the only installer there is only one copy anyway, so the question is
   really whether the *other* apps ever read a theme directly. Currently they don't.
7. **Should `bundleID:` entries be user-creatable** ("this app wherever it lives"), or
   exist only as legacy fallbacks? A second way to key one app is a second way to be
   confused about which one applied.
8. **What happens to a Zap user who never installs Pict and had custom icons?**
   Migration moves them into the shared store and Zap keeps *drawing* them — reading
   is not the part that moved. But they can no longer change or add one. That is the
   right behaviour and it needs to be said in the UI rather than discovered.

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
