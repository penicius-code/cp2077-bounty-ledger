// Cyberslop Bounty Ledger 1.1.3 (2026-11-06; 1.0.1: processing time default 10 game min;
// 1.1.0: Deep Scan warrants, see CyberslopWarrants.reds; Cashflow source tag on payouts;
// 1.1.1: a claimed target V tags for I Want Them Alive pickup is withdrawn from the NCPD batch;
// 1.1.2: killing a warrant target is reported again, scan list reset on load;
// 1.1.3: open claims are kept in the save (death downgrade and IWTA withdrawal survive a load);
// Regina Jones brokers the NCPD claims: HUD lines at claim, payout and withdrawal;
// 1.1.4: claim details, a saved event journal and lifetime totals for the CET window
// "Cyberslop NCPD Uplink" (bin\x64\plugins\cyber_engine_tweaks\mods\CyberslopBountyUplink);
// 1.1.5 (2026-11-07): public WithdrawByHash for Cyberslop TT Clients (a target Trauma Team extracted
// survived, so its claim is voided);
// 1.1.6 (2026-11-07 review): a Trauma Team void is journalled as such, not as a FixerNet sale)
// NCPD street bounties that read like a warrant system instead of a level-scaled loot drop.
//   1. Price by wanted stars. The scanner's stars come from the enemy class (Bounty Class Stars
//      Fix: Trash/Weak 1, Normal 2, Rare 3, Officer/Elite 4, Boss 5); every BountyReward.Generic
//      bounty pays the star price from Mod Settings. Named bounties (Placide, Woodman, NCPD
//      Most Wanted...) keep their record value (EconomyPunk), without rarity multipliers.
//   2. Alive pays full, dead pays the dead rate (default 50 %). Alive = knocked out with a
//      non-lethal takedown and not dead. A claimed-alive target that dies before the payout
//      drops to the dead rate.
//   3. No scan, no claim: V's optics must have pulled the record (scanner tooltip or a
//      completed scan) before the target went down.
//   4. NCPD pays later: claims collect into one batch, paid after the processing time in game
//      minutes, with the vanilla "Bounty collected" banner and an NCPD message. Persists in saves.
// Street cred and kill XP stay vanilla. Hooks: BountyManager.SetBountyFromID / CompleteBounty,
// ScriptedPuppet.RewardKiller, NPCPuppet.CompileScannerChunks,
// BountyCollectedNotificationQueue.OnBountyCompletionEvent (all wraps).
module CyberslopBountyLedger

@if(ModuleExists("NightCityFinance.Compat"))
import NightCityFinance.Compat.*
@if(ModuleExists("CyberslopCashflow"))
import CyberslopCashflow.*

// Night City Finance books the delayed payout as NCPD income (as it does vanilla bounties).
@if(ModuleExists("NightCityFinance.Compat"))
func CSBL_TellNCF(amount: Int32) -> Bool { return NCFCompat.ReportIncome(amount, NCFCompat.KindNCPD()); }
@if(!ModuleExists("NightCityFinance.Compat"))
func CSBL_TellNCF(amount: Int32) -> Bool { return false; }


// Cyberslop Cashflow books the payout under NCPD bounties.
@if(ModuleExists("CyberslopCashflow"))
func CSBL_TagCashflow(gi: GameInstance, detail: String) -> Void { CashflowBook.TagNow(gi, CashflowCat.Bounty(), detail, 3.0); }
@if(!ModuleExists("CyberslopCashflow"))
func CSBL_TagCashflow(gi: GameInstance, detail: String) -> Void {}

// ---------------------------------------------------------------- settings

public class BountyLedgerSettings extends ScriptableSystem {

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Rules")
  @runtimeProperty("ModSettings.displayName", "Enabled")
  @runtimeProperty("ModSettings.description", "Off = vanilla bounty chain (Bounties Restored, Lifepath Bonuses) pays instantly again. Claims already queued are still paid.")
  public let enabled: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Rules")
  @runtimeProperty("ModSettings.displayName", "Require scan")
  @runtimeProperty("ModSettings.description", "Only targets your optics scanned before they went down can be claimed.")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let requireScan: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Rules")
  @runtimeProperty("ModSettings.displayName", "Alive rate (%)")
  @runtimeProperty("ModSettings.description", "Share of the bounty paid for a target knocked out non-lethally.")
  @runtimeProperty("ModSettings.step", "5")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "200")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let alivePercent: Int32 = 100;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Rules")
  @runtimeProperty("ModSettings.displayName", "Dead rate (%)")
  @runtimeProperty("ModSettings.description", "Share of the bounty paid for a target killed (lethal force).")
  @runtimeProperty("ModSettings.step", "5")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "200")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let deadPercent: Int32 = 50;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Rules")
  @runtimeProperty("ModSettings.displayName", "NCPD processing time (game minutes)")
  @runtimeProperty("ModSettings.description", "Claims collect into one batch, paid this many game minutes after the first claim. 0 = within seconds.")
  @runtimeProperty("ModSettings.step", "5")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "360")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let processingMinutes: Int32 = 10;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Prices")
  @runtimeProperty("ModSettings.displayName", "1 star (eddies)")
  @runtimeProperty("ModSettings.description", "Trash and Weak enemies: petty record, usually no warrant.")
  @runtimeProperty("ModSettings.step", "10")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "10000")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let price1: Int32 = 0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Prices")
  @runtimeProperty("ModSettings.displayName", "2 stars (eddies)")
  @runtimeProperty("ModSettings.description", "Normal enemies: street ganger.")
  @runtimeProperty("ModSettings.step", "10")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "10000")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let price2: Int32 = 50;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Prices")
  @runtimeProperty("ModSettings.displayName", "3 stars (eddies)")
  @runtimeProperty("ModSettings.description", "Rare enemies: armed felon.")
  @runtimeProperty("ModSettings.step", "10")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "10000")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let price3: Int32 = 150;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Prices")
  @runtimeProperty("ModSettings.displayName", "4 stars (eddies)")
  @runtimeProperty("ModSettings.description", "Officer and Elite enemies: lieutenant, enforcer.")
  @runtimeProperty("ModSettings.step", "10")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "10000")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let price4: Int32 = 400;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Prices")
  @runtimeProperty("ModSettings.displayName", "5 stars (eddies)")
  @runtimeProperty("ModSettings.description", "Boss-class enemies without a named bounty: wanted killer.")
  @runtimeProperty("ModSettings.step", "10")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "10000")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let price5: Int32 = 1000;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Warrants")
  @runtimeProperty("ModSettings.displayName", "Deep Scan warrants")
  @runtimeProperty("ModSettings.description", "Civilians whose Kiroshi Deep Scan record shows an active warrant can be brought in alive (non-lethal knockout) for an NCPD fee, paid with the next batch. Killing them pays nothing and stays murder.")
  @runtimeProperty("ModSettings.dependency", "enabled")
  public let warrants: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Warrants")
  @runtimeProperty("ModSettings.displayName", "Lowest warrant class (stars)")
  @runtimeProperty("ModSettings.description", "2 = every active warrant (theft, fraud, failure to appear...), 3 = assault and parole violations up, 4 = violent felonies and corpo extraditions, 5 = murder only.")
  @runtimeProperty("ModSettings.step", "1")
  @runtimeProperty("ModSettings.min", "2")
  @runtimeProperty("ModSettings.max", "5")
  @runtimeProperty("ModSettings.dependency", "warrants")
  public let warrantMinStars: Int32 = 2;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Warrants")
  @runtimeProperty("ModSettings.displayName", "Warrant fee (% of the star price)")
  @runtimeProperty("ModSettings.description", "Fee for bringing a warrant in alive, as a share of the star prices above.")
  @runtimeProperty("ModSettings.step", "5")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "200")
  @runtimeProperty("ModSettings.dependency", "warrants")
  public let warrantRate: Int32 = 100;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Warrants")
  @runtimeProperty("ModSettings.displayName", "Lawful arrest")
  @runtimeProperty("ModSettings.description", "A scanned warrant target taken down by V is an arrest: no assault report to NCPD (vanilla and NCPD Duty Expansion). A kill still counts as murder.")
  @runtimeProperty("ModSettings.dependency", "warrants")
  public let warrantLegalCover: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Warrants")
  @runtimeProperty("ModSettings.displayName", "Warrant notice")
  @runtimeProperty("ModSettings.description", "HUD line when your optics flag a warrant: offence and fee.")
  @runtimeProperty("ModSettings.dependency", "warrants")
  public let warrantNotice: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Display")
  @runtimeProperty("ModSettings.displayName", "Regina claim messages")
  @runtimeProperty("ModSettings.description", "HUD lines from Regina Jones when a claim is filed, paid or withdrawn (the vanilla Bounty collected banner shows either way).")
  public let payoutMessage: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Bounty Ledger")
  @runtimeProperty("ModSettings.category", "Display")
  @runtimeProperty("ModSettings.displayName", "Log to redscript log")
  @runtimeProperty("ModSettings.description", "[BountyLedger] lines for every price, claim, downgrade and payout. Events only.")
  public let debugLog: Bool = true;

  private func OnAttach() -> Void {
    ModSettings.RegisterListenerToClass(this);
  }

  private func OnDetach() -> Void {
    ModSettings.UnregisterListenerToClass(this);
  }

  public final func StarPrice(stars: Int32) -> Int32 {
    if stars <= 1 { return this.price1; };
    if stars == 2 { return this.price2; };
    if stars == 3 { return this.price3; };
    if stars == 4 { return this.price4; };
    return this.price5;
  }

  public static func Get(gi: GameInstance) -> ref<BountyLedgerSettings> {
    return GameInstance.GetScriptableSystemsContainer(gi).Get(n"CyberslopBountyLedger.BountyLedgerSettings") as BountyLedgerSettings;
  }
}

// ---------------------------------------------------------------- timer

public class BountyLedgerTick extends DelayCallback {
  public let ledger: wref<BountyLedger>;
  public let gen: Int32;

  public func Call() -> Void {
    if IsDefined(this.ledger) {
      this.ledger.Tick(this.gen);
    };
  }
}

// ---------------------------------------------------------------- the ledger

public class BountyLedger extends ScriptableSystem {

  // Open batch (kept in the save).
  public persistent let pendingTotal: Int32 = 0;
  public persistent let pendingClaims: Int32 = 0;
  public persistent let pendingDeceased: Int32 = 0;
  public persistent let dueAt: Float = 0.0;

  // Claims of the open batch, for the death downgrade and the IWTA withdrawal (kept in the
  // save since 1.1.3; the hashes are rebuilt from the IDs on load).
  private persistent let m_claimIDs: array<EntityID>;
  private let m_claimHashes: array<Uint32>;
  private persistent let m_claimAlivePay: array<Int32>;
  private persistent let m_claimDeadPay: array<Int32>;
  private persistent let m_claimIsAlive: array<Bool>;
  // 1.1.4, for the window: record, stars, kind (0 bounty, 1 warrant) per claim; batch opening time.
  private persistent let m_claimRecords: array<TweakDBID>;
  private persistent let m_claimStars: array<Int32>;
  private persistent let m_claimKind: array<Int32>;
  public persistent let openedAt: Float = 0.0;
  // Lifetime (since 1.1.4).
  public persistent let lifetimePaid: Int32 = 0;
  public persistent let lifetimeClaims: Int32 = 0;
  public persistent let lifetimeBatches: Int32 = 0;
  public persistent let lastPayoutAt: Float = 0.0;
  public persistent let lastPayoutAmount: Int32 = 0;
  // Event journal (newest last, 40 kept). Labels (warrant offences) are this session only.
  private persistent let m_jTime: array<Float>;
  private persistent let m_jKind: array<Int32>;
  private persistent let m_jAmount: array<Int32>;
  private persistent let m_jRecord: array<TweakDBID>;
  private persistent let m_jAux: array<Int32>;
  private let m_jLabel: array<String>;
  // Every NPC whose scanner record V's optics displayed (newest last).
  private let m_scanned: array<Uint32>;
  // Neutralization in progress (set by the RewardKiller wrap, read by CompleteBounty).
  private let m_ctxHash: Uint32;
  private let m_ctxSet: Bool;
  private let m_ctxAlive: Bool;
  private let m_tickQueued: Bool;
  private let m_tickQueuedAt: Float;
  private let m_tickGen: Int32;

  public static func Get(gi: GameInstance) -> ref<BountyLedger> {
    return GameInstance.GetScriptableSystemsContainer(gi).Get(n"CyberslopBountyLedger.BountyLedger") as BountyLedger;
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.RestoreClaims();
    this.RestoreJournal();
    // Scans belong to this session (1.1.2): an old hash must not stand in for a new NPC.
    ArrayClear(this.m_scanned);
    this.m_ctxSet = false;
    this.m_tickQueued = false;
    this.ScheduleTick();
  }

  private final func ClearSession() -> Void {
    ArrayClear(this.m_claimIDs);
    ArrayClear(this.m_claimHashes);
    ArrayClear(this.m_claimAlivePay);
    ArrayClear(this.m_claimDeadPay);
    ArrayClear(this.m_claimIsAlive);
    ArrayClear(this.m_claimRecords);
    ArrayClear(this.m_claimStars);
    ArrayClear(this.m_claimKind);
  }

  private final func EraseClaim(i: Int32) -> Void {
    ArrayErase(this.m_claimIDs, i);
    ArrayErase(this.m_claimHashes, i);
    ArrayErase(this.m_claimAlivePay, i);
    ArrayErase(this.m_claimDeadPay, i);
    ArrayErase(this.m_claimIsAlive, i);
    if i < ArraySize(this.m_claimRecords) { ArrayErase(this.m_claimRecords, i); };
    if i < ArraySize(this.m_claimStars) { ArrayErase(this.m_claimStars, i); };
    if i < ArraySize(this.m_claimKind) { ArrayErase(this.m_claimKind, i); };
  }

  private final func PushClaimInfo(rec: TweakDBID, stars: Int32, kind: Int32) -> Void {
    ArrayPush(this.m_claimRecords, rec);
    ArrayPush(this.m_claimStars, stars);
    ArrayPush(this.m_claimKind, kind);
  }

  // --- journal (1.1.4)
  // Kinds: 1 claim alive, 2 claim deceased, 3 warrant served, 4 died in custody, 5 withdrawn (FixerNet),
  // 6 transfer cleared (aux = claims), 7 no claim, not scanned, 8 no claim, no NCPD link,
  // 9 warrant flagged (aux = stars), 10 warrant target killed.
  public final func Note(kind: Int32, amount: Int32, rec: TweakDBID, aux: Int32, label: String) -> Void {
    ArrayPush(this.m_jTime, this.Now());
    ArrayPush(this.m_jKind, kind);
    ArrayPush(this.m_jAmount, amount);
    ArrayPush(this.m_jRecord, rec);
    ArrayPush(this.m_jAux, aux);
    ArrayPush(this.m_jLabel, label);
    while ArraySize(this.m_jTime) > 40 {
      ArrayErase(this.m_jTime, 0);
      ArrayErase(this.m_jKind, 0);
      ArrayErase(this.m_jAmount, 0);
      ArrayErase(this.m_jRecord, 0);
      ArrayErase(this.m_jAux, 0);
      ArrayErase(this.m_jLabel, 0);
    };
  }

  private final func RestoreJournal() -> Void {
    let n: Int32 = Min(Min(ArraySize(this.m_jTime), ArraySize(this.m_jKind)), Min(Min(ArraySize(this.m_jAmount), ArraySize(this.m_jRecord)), ArraySize(this.m_jAux)));
    while ArraySize(this.m_jTime) > n { ArrayErase(this.m_jTime, 0); };
    while ArraySize(this.m_jKind) > n { ArrayErase(this.m_jKind, 0); };
    while ArraySize(this.m_jAmount) > n { ArrayErase(this.m_jAmount, 0); };
    while ArraySize(this.m_jRecord) > n { ArrayErase(this.m_jRecord, 0); };
    while ArraySize(this.m_jAux) > n { ArrayErase(this.m_jAux, 0); };
    ArrayClear(this.m_jLabel);
    while ArraySize(this.m_jLabel) < n { ArrayPush(this.m_jLabel, ""); };
  }

  // Name as the scanner shows it: full name, else name, else faction + archetype.
  public final static func RecordName(rec: TweakDBID) -> String {
    let r: ref<Character_Record> = TweakDBInterface.GetCharacterRecord(rec);
    let arch: String;
    let fac: String;
    if !IsDefined(r) {
      return "unknown";
    };
    if IsNameValid(r.FullDisplayName()) {
      return GetLocalizedText(LocKeyToString(r.FullDisplayName()));
    };
    if IsNameValid(r.DisplayName()) {
      return GetLocalizedText(LocKeyToString(r.DisplayName()));
    };
    fac = BountyLedger.RecordFaction(rec);
    if IsDefined(r.ArchetypeData()) && IsDefined(r.ArchetypeData().Type()) {
      arch = GetLocalizedTextByKey(r.ArchetypeData().Type().LocalizedName());
    };
    if StrLen(fac) > 0 && StrLen(arch) > 0 { return fac + " " + StrLower(arch); };
    if StrLen(arch) > 0 { return arch; };
    if StrLen(fac) > 0 { return fac; };
    return "unknown";
  }

  public final static func RecordFaction(rec: TweakDBID) -> String {
    let r: ref<Character_Record> = TweakDBInterface.GetCharacterRecord(rec);
    if !IsDefined(r) || !IsDefined(r.Affiliation()) {
      return "";
    };
    return GetLocalizedText(LocKeyToString(r.Affiliation().LocalizedName()));
  }

  // --- window accessors (CET, read-only)
  public final func ClaimCount() -> Int32 = ArraySize(this.m_claimIDs)
  public final func ClaimName(i: Int32) -> String {
    if i < 0 || i >= ArraySize(this.m_claimRecords) { return "unknown"; };
    return BountyLedger.RecordName(this.m_claimRecords[i]);
  }
  public final func ClaimFaction(i: Int32) -> String {
    if i < 0 || i >= ArraySize(this.m_claimRecords) { return ""; };
    return BountyLedger.RecordFaction(this.m_claimRecords[i]);
  }
  public final func ClaimStars(i: Int32) -> Int32 {
    if i < 0 || i >= ArraySize(this.m_claimStars) { return 0; };
    return this.m_claimStars[i];
  }
  public final func ClaimIsWarrant(i: Int32) -> Bool {
    if i < 0 || i >= ArraySize(this.m_claimKind) { return false; };
    return this.m_claimKind[i] == 1;
  }
  public final func ClaimAlive(i: Int32) -> Bool {
    if i < 0 || i >= ArraySize(this.m_claimIsAlive) { return false; };
    return this.m_claimIsAlive[i];
  }
  public final func ClaimPay(i: Int32) -> Int32 {
    if i < 0 || i >= ArraySize(this.m_claimIsAlive) { return 0; };
    return this.m_claimIsAlive[i] ? this.m_claimAlivePay[i] : this.m_claimDeadPay[i];
  }
  // -1 = body not loaded (out of range), else metres from V.
  public final func ClaimDistance(i: Int32) -> Float {
    let ent: ref<GameObject>;
    let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
    if i < 0 || i >= ArraySize(this.m_claimIDs) || !IsDefined(player) { return -1.0; };
    ent = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_claimIDs[i]) as GameObject;
    if !IsDefined(ent) { return -1.0; };
    return Vector4.Distance(ent.GetWorldPosition(), player.GetWorldPosition());
  }
  public final func ClaimBodyDead(i: Int32) -> Bool {
    let ent: ref<GameObject>;
    if i < 0 || i >= ArraySize(this.m_claimIDs) { return false; };
    ent = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_claimIDs[i]) as GameObject;
    return IsDefined(ent) && ent.IsDead();
  }
  public final func BatchOpenedAt() -> Float {
    let s: ref<BountyLedgerSettings> = this.Settings();
    if this.openedAt > 0.0 || !IsDefined(s) { return this.openedAt; };
    return this.dueAt - Cast<Float>(s.processingMinutes) * 60.0;
  }
  public final func JournalCount() -> Int32 = ArraySize(this.m_jTime)
  public final func JournalTime(i: Int32) -> Float {
    if i < 0 || i >= ArraySize(this.m_jTime) { return 0.0; };
    return this.m_jTime[i];
  }
  public final func JournalKind(i: Int32) -> Int32 {
    if i < 0 || i >= ArraySize(this.m_jKind) { return 0; };
    return this.m_jKind[i];
  }
  public final func JournalText(i: Int32) -> String {
    let k: Int32;
    let a: Int32;
    let x: Int32;
    let label: String;
    let name: String;
    if i < 0 || i >= ArraySize(this.m_jKind) { return ""; };
    k = this.m_jKind[i];
    a = this.m_jAmount[i];
    x = this.m_jAux[i];
    label = i < ArraySize(this.m_jLabel) ? this.m_jLabel[i] : "";
    if StrLen(label) == 0 && x > 0 && (k == 3 || k == 9 || k == 10) {
      label = "class " + IntToString(x) + " warrant";
    };
    name = (k == 6) ? "" : BountyLedger.RecordName(this.m_jRecord[i]);
    if k == 1 { return "Claim filed: " + name + ", " + IntToString(x) + " stars, alive, +" + IntToString(a); };
    if k == 2 { return "Claim filed: " + name + ", " + IntToString(x) + " stars, deceased, +" + IntToString(a); };
    if k == 3 { return "Warrant served: " + label + ", +" + IntToString(a); };
    if k == 4 { return "Died before the transfer: " + name + ", -" + IntToString(a); };
    if k == 5 { return (x == 1 ? "Claim voided, Trauma Team extraction: " : "Claim pulled, handed to FixerNet: ") + name + ", -" + IntToString(a); };
    if k == 6 { return "NCPD transfer cleared: " + IntToString(a) + " eddies, " + IntToString(x) + (x == 1 ? " claim" : " claims"); };
    if k == 7 { return "No claim: " + name + ", no scan on file (" + IntToString(a) + " lost)"; };
    if k == 8 { return "No claim: " + name + ", optics have no NCPD link"; };
    if k == 9 { return "Warrant flagged: " + label + ", fee " + IntToString(a); };
    if k == 10 { return "Warrant target killed: " + label + ", no fee"; };
    return "";
  }

  // After a load: the saved claim arrays must line up with each other and with the open batch
  // (a 1.1.2 save has a batch but no arrays); otherwise drop them, the batch total still pays.
  private final func RestoreClaims() -> Void {
    let n: Int32 = ArraySize(this.m_claimIDs);
    let i: Int32 = 0;
    ArrayClear(this.m_claimHashes);
    if this.pendingClaims <= 0 || n != this.pendingClaims || ArraySize(this.m_claimAlivePay) != n || ArraySize(this.m_claimDeadPay) != n || ArraySize(this.m_claimIsAlive) != n {
      if n > 0 {
        this.Log("saved claims dropped | " + IntToString(n) + " saved, batch has " + IntToString(this.pendingClaims));
      };
      this.ClearSession();
      return;
    };
    while i < n {
      ArrayPush(this.m_claimHashes, EntityID.GetHash(this.m_claimIDs[i]));
      i += 1;
    };
    if ArraySize(this.m_claimRecords) != n || ArraySize(this.m_claimStars) != n || ArraySize(this.m_claimKind) != n {
      ArrayClear(this.m_claimRecords);
      ArrayClear(this.m_claimStars);
      ArrayClear(this.m_claimKind);
      i = 0;
      while i < n {
        this.PushClaimInfo(TDBID.None(), 0, this.m_claimDeadPay[i] == 0 ? 1 : 0);
        i += 1;
      };
    };
    this.Log("saved claims restored | " + IntToString(n) + " | batch " + IntToString(this.pendingTotal) + " eb, due in " + FloatToStringPrec((this.dueAt - this.Now()) / 60.0, 1) + " game min");
  }

  // Regina Jones brokers V's NCPD claims (she runs the Watson bounty and cyberpsycho reports).
  public final func ReginaLine(text: String, seconds: Float) -> Void {
    let msg: SimpleScreenMessage;
    msg.isShown = true;
    msg.duration = seconds;
    msg.message = "Regina Jones: " + text;
    msg.isInstant = true;
    msg.type = SimpleMessageType.Police;
    GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_Notifications).SetVariant(GetAllBlackboardDefs().UI_Notifications.WarningMessage, ToVariant(msg), true);
  }

  // Claim filed: amount, batch and time to the transfer (game minutes).
  private final func ClaimLine(pay: Int32, what: String) -> Void {
    let s: ref<BountyLedgerSettings> = this.Settings();
    let mins: Int32;
    if !IsDefined(s) || !s.payoutMessage {
      return;
    };
    mins = Max(1, CeilF((this.dueAt - this.Now()) / 60.0));
    if this.pendingClaims <= 1 {
      this.ReginaLine(what + " logged with NCPD, " + IntToString(pay) + " eddies. I'll watch the transfer, clears in about " + IntToString(mins) + " min.", 5.0);
    } else {
      this.ReginaLine(what + " added to your NCPD file, " + IntToString(pay) + " eddies. " + IntToString(this.pendingClaims) + " claims, " + IntToString(this.pendingTotal) + " eddies, clears in about " + IntToString(mins) + " min.", 5.0);
    };
  }

  private final func Settings() -> ref<BountyLedgerSettings> {
    return BountyLedgerSettings.Get(this.GetGameInstance());
  }

  public final func Active() -> Bool {
    let s: ref<BountyLedgerSettings> = this.Settings();
    return IsDefined(s) && s.enabled;
  }

  public final func Log(msg: String) -> Void {
    let s: ref<BountyLedgerSettings> = this.Settings();
    if IsDefined(s) && s.debugLog {
      FTLog("[BountyLedger] " + msg);
    };
  }

  private final func Now() -> Float {
    return GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTimeStamp();
  }

  // --- pricing

  public final static func ClassStars(target: wref<NPCPuppet>) -> Int32 {
    let r: gamedataNPCRarity = target.GetNPCRarity();
    if Equals(r, gamedataNPCRarity.Normal) { return 2; };
    if Equals(r, gamedataNPCRarity.Rare) { return 3; };
    if Equals(r, gamedataNPCRarity.Officer) || Equals(r, gamedataNPCRarity.Elite) { return 4; };
    if Equals(r, gamedataNPCRarity.Boss) { return 5; };
    return 1;
  }

  // Price of a bounty record on this target; -1 = leave the vanilla value.
  public final func PriceFor(bountyID: TweakDBID, target: wref<NPCPuppet>, out stars: Int32, out generic: Bool) -> Int32 {
    let rec: wref<Bounty_Record> = TweakDBInterface.GetBountyRecord(bountyID);
    let currencyArr: array<wref<CurrencyReward_Record>>;
    let mods: array<wref<StatModifier_Record>>;
    let s: ref<BountyLedgerSettings> = this.Settings();
    stars = BountyLedger.ClassStars(target);
    generic = false;
    if !IsDefined(rec) || !IsDefined(rec.Reward()) || !IsDefined(s) {
      return -1;
    };
    if rec.Reward().GetID() == t"BountyReward.Generic" {
      generic = true;
      return s.StarPrice(stars);
    };
    rec.Reward().CurrencyPackage(currencyArr);
    if ArraySize(currencyArr) == 0 {
      return -1;
    };
    currencyArr[0].QuantityModifiers(mods);
    return Cast<Int32>(RPGManager.CalculateStatModifiers(mods, target.GetGame(), GetPlayer(target.GetGame()), Cast<StatsObjectID>(target.GetEntityID())));
  }

  // --- scan evidence

  public final func NoteScanned(id: EntityID) -> Void {
    let h: Uint32 = EntityID.GetHash(id);
    if ArrayContains(this.m_scanned, h) {
      return;
    };
    ArrayPush(this.m_scanned, h);
    if ArraySize(this.m_scanned) > 512 {
      ArrayErase(this.m_scanned, 0);
    };
    if this.pendingClaims > 0 {
      this.ScheduleTick();
    };
  }

  // --- neutralization context

  public final func BeginNeutralize(puppet: ref<ScriptedPuppet>, killType: gameKillType, nonlethal: Bool) -> Void {
    let h: Uint32 = EntityID.GetHash(puppet.GetEntityID());
    this.m_ctxHash = h;
    this.m_ctxSet = true;
    this.m_ctxAlive = Equals(killType, gameKillType.Defeat) && nonlethal && !puppet.IsDead();
    if Equals(killType, gameKillType.Normal) {
      this.DowngradeIfClaimedAlive(h, "died");
    };
    if this.pendingClaims > 0 {
      this.ScheduleTick();
    };
  }

  public final func EndNeutralize(puppet: ref<ScriptedPuppet>) -> Void {
    if this.m_ctxSet && this.m_ctxHash == EntityID.GetHash(puppet.GetEntityID()) {
      this.m_ctxSet = false;
    };
  }

  private final func DowngradeIfClaimedAlive(h: Uint32, why: String) -> Void {
    let i: Int32 = ArrayFindFirst(this.m_claimHashes, h);
    let cut: Int32;
    if i < 0 || !this.m_claimIsAlive[i] {
      return;
    };
    cut = this.m_claimAlivePay[i] - this.m_claimDeadPay[i];
    this.m_claimIsAlive[i] = false;
    this.Note(4, cut, i < ArraySize(this.m_claimRecords) ? this.m_claimRecords[i] : TDBID.None(), 0, "");
    this.pendingTotal = Max(0, this.pendingTotal - cut);
    this.pendingDeceased += 1;
    this.Log("downgrade (" + why + ") alive " + IntToString(this.m_claimAlivePay[i]) + " -> dead " + IntToString(this.m_claimDeadPay[i]) + " | batch " + IntToString(this.pendingTotal) + " eb / " + IntToString(this.pendingClaims));
  }

  // --- claims (called before the vanilla CompleteBounty chain runs)

  public final func FileClaim(target: wref<NPCPuppet>) -> Void {
    let gi: GameInstance = target.GetGame();
    let player: ref<PlayerPuppet> = GetPlayer(gi);
    let s: ref<BountyLedgerSettings> = this.Settings();
    let bounty: Bounty = target.GetBounty();
    let h: Uint32 = EntityID.GetHash(target.GetEntityID());
    let amount: Int32;
    let hasLink: Bool;
    let scannedNative: Bool;
    let scannedUI: Bool;
    let alive: Bool;
    let pay: Int32;
    let alivePay: Int32;
    let deadPay: Int32;
    let how: String;
    let name: String;
    if !IsDefined(player) || !IsDefined(s) || bounty.m_awarded || ArrayContains(this.m_claimHashes, h) {
      return;
    };
    if ArraySize(bounty.m_transgressions) <= 0 {
      bounty = BountyManager.GenerateBounty(target);
    };
    if bounty.m_filteredOut || ArraySize(bounty.m_transgressions) <= 0 {
      return;
    };
    amount = bounty.m_moneyAmount;
    // The vanilla chain pays m_moneyAmount at once; it pays 0 now (street cred and XP stay).
    bounty.m_moneyAmount = 0;
    target.CSBL_SetBountyNow(bounty);

    name = TDBID.ToStringDEBUG(target.GetRecordID());
    hasLink = GameInstance.GetStatsSystem(gi).GetStatValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatType.HasLinkToBountySystem) > 0.00;
    if amount <= 0 || !hasLink {
      this.Log("no claim " + name + " | price " + IntToString(amount) + (hasLink ? "" : " | optics have no NCPD link"));
      if amount > 0 {
        this.Note(8, amount, target.GetRecordID(), 0, "");
      };
      return;
    };
    scannedNative = target.IsScanned();
    scannedUI = ArrayContains(this.m_scanned, h);
    if s.requireScan && !scannedNative && !scannedUI {
      this.Log("no claim " + name + " | not scanned | price " + IntToString(amount));
      this.Note(7, (amount * s.alivePercent + 50) / 100, target.GetRecordID(), 0, "");
      return;
    };
    if this.m_ctxSet && this.m_ctxHash == h {
      alive = this.m_ctxAlive;
      how = alive ? "alive" : "dead";
    } else {
      alive = !target.IsDead() && ScriptedPuppet.IsUnconscious(target);
      how = alive ? "alive(state)" : "dead(state)";
    };
    alivePay = (amount * s.alivePercent + 50) / 100;
    deadPay = (amount * s.deadPercent + 50) / 100;
    pay = alive ? alivePay : deadPay;
    if pay <= 0 {
      this.Log("no claim " + name + " | " + how + " pays 0");
      return;
    };
    if this.pendingClaims <= 0 {
      this.openedAt = this.Now();
      this.dueAt = this.openedAt + Cast<Float>(s.processingMinutes) * 60.0;
      this.pendingTotal = 0;
      this.pendingDeceased = 0;
      this.ClearSession();
    };
    this.pendingTotal += pay;
    this.pendingClaims += 1;
    if !alive {
      this.pendingDeceased += 1;
    };
    ArrayPush(this.m_claimIDs, target.GetEntityID());
    ArrayPush(this.m_claimHashes, h);
    ArrayPush(this.m_claimAlivePay, alivePay);
    ArrayPush(this.m_claimDeadPay, deadPay);
    ArrayPush(this.m_claimIsAlive, alive);
    this.PushClaimInfo(target.GetRecordID(), BountyLedger.ClassStars(target), 0);
    this.Note(alive ? 1 : 2, pay, target.GetRecordID(), BountyLedger.ClassStars(target), "");
    this.Log("claim " + name + " | " + IntToString(BountyLedger.ClassStars(target)) + " stars | price " + IntToString(amount) + " | " + how + " -> " + IntToString(pay) + " | scan native=" + (scannedNative ? "1" : "0") + " ui=" + (scannedUI ? "1" : "0") + " | batch " + IntToString(this.pendingTotal) + " eb / " + IntToString(this.pendingClaims) + ", due in " + FloatToStringPrec((this.dueAt - this.Now()) / 60.0, 1) + " game min");
    this.ClaimLine(pay, alive ? "Bounty, brought in alive," : "Bounty, deceased,");
    this.ScheduleTick();
  }

  // --- warrant claims (CyberslopWarrants.reds): alive only, a later death voids the fee.

  public final func FileWarrantClaim(target: wref<NPCPuppet>, pay: Int32, label: String, stars: Int32) -> Bool {
    let s: ref<BountyLedgerSettings> = this.Settings();
    let h: Uint32;
    if !IsDefined(target) || !IsDefined(s) || pay <= 0 {
      return false;
    };
    h = EntityID.GetHash(target.GetEntityID());
    if ArrayContains(this.m_claimHashes, h) {
      return false;
    };
    if this.pendingClaims <= 0 {
      this.openedAt = this.Now();
      this.dueAt = this.openedAt + Cast<Float>(s.processingMinutes) * 60.0;
      this.pendingTotal = 0;
      this.pendingDeceased = 0;
      this.ClearSession();
    };
    this.pendingTotal += pay;
    this.pendingClaims += 1;
    ArrayPush(this.m_claimIDs, target.GetEntityID());
    ArrayPush(this.m_claimHashes, h);
    ArrayPush(this.m_claimAlivePay, pay);
    ArrayPush(this.m_claimDeadPay, 0);
    ArrayPush(this.m_claimIsAlive, true);
    this.PushClaimInfo(target.GetRecordID(), stars, 1);
    this.Note(3, pay, target.GetRecordID(), stars, label);
    this.Log("warrant claim " + TDBID.ToStringDEBUG(target.GetRecordID()) + " | " + label + " | alive -> " + IntToString(pay) + " | batch " + IntToString(this.pendingTotal) + " eb / " + IntToString(this.pendingClaims) + ", due in " + FloatToStringPrec((this.dueAt - this.Now()) / 60.0, 1) + " game min");
    this.ClaimLine(pay, "Warrant served (" + label + "),");
    this.ScheduleTick();
    return true;
  }

  // --- payout

  // One 5 s poll while a batch is open. A poll lost to a save load or a time skip
  // (queued > 15 game min ago, or "in the future") is replaced; the old one is ignored.
  private final func ScheduleTick() -> Void {
    let cb: ref<BountyLedgerTick>;
    let now: Float = this.Now();
    if this.m_tickQueued && now >= this.m_tickQueuedAt && now - this.m_tickQueuedAt < 900.0 {
      return;
    };
    this.m_tickGen += 1;
    this.m_tickQueued = true;
    this.m_tickQueuedAt = now;
    cb = new BountyLedgerTick();
    cb.ledger = this;
    cb.gen = this.m_tickGen;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 5.0, false);
  }

  public final func Tick(gen: Int32) -> Void {
    if gen != this.m_tickGen {
      return;
    };
    this.m_tickQueued = false;
    if this.pendingClaims <= 0 {
      return;
    };
    this.CustodyCheck();
    if this.pendingClaims <= 0 {
      return;
    };
    if this.Now() >= this.dueAt && IsDefined(GetPlayer(this.GetGameInstance())) {
      this.Payout();
      return;
    };
    this.ScheduleTick();
  }

  // --- I Want Them Alive (1.1.1): a target V tags for FixerNet pickup belongs to the fixer, so
  // its NCPD claim is withdrawn (one payer per perp). IWTA has no module to test at compile time,
  // so its ScriptedPuppet.BAT_IsMarkedForPickup is looked up at runtime (Codeware reflection);
  // without IWTA this does nothing.
  public final func CustodyCheck() -> Void {
    let gi: GameInstance = this.GetGameInstance();
    let cls: ref<ReflectionClass>;
    let fn: ref<ReflectionMemberFunc>;
    let ent: ref<ScriptedPuppet>;
    let i: Int32;
    if ArraySize(this.m_claimIDs) == 0 {
      return;
    };
    cls = Reflection.GetClass(n"ScriptedPuppet");
    if !IsDefined(cls) {
      return;
    };
    fn = cls.GetFunction(n"BAT_IsMarkedForPickup");
    if !IsDefined(fn) {
      return;
    };
    i = ArraySize(this.m_claimIDs) - 1;
    while i >= 0 {
      ent = GameInstance.FindEntityByID(gi, this.m_claimIDs[i]) as ScriptedPuppet;
      if IsDefined(ent) && FromVariant<Bool>(fn.Call(ent)) {
        this.WithdrawAt(i, "FixerNet custody, I Want Them Alive", "");
      };
      i -= 1;
    };
  }

  // 1.1.5: another mod voids the claim on one target (Cyberslop TT Clients: Trauma Team extracted
  // the target, it survived). False = no open claim on it (none filed, or already paid).
  public final func WithdrawByHash(h: Uint32, why: String, line: String) -> Bool {
    let i: Int32 = ArrayFindFirst(this.m_claimHashes, h);
    if i < 0 {
      this.Log("withdraw request (" + why + "): no open claim on that target");
      return false;
    };
    this.WithdrawAt(i, why, line);
    return true;
  }

  private final func WithdrawAt(i: Int32, why: String, line: String) -> Void {
    let s: ref<BountyLedgerSettings> = this.Settings();
    let pay: Int32 = this.m_claimIsAlive[i] ? this.m_claimAlivePay[i] : this.m_claimDeadPay[i];
    this.pendingTotal = Max(0, this.pendingTotal - pay);
    this.pendingClaims = Max(0, this.pendingClaims - 1);
    if !this.m_claimIsAlive[i] {
      this.pendingDeceased = Max(0, this.pendingDeceased - 1);
    };
    this.Note(5, pay, i < ArraySize(this.m_claimRecords) ? this.m_claimRecords[i] : TDBID.None(), StrLen(line) > 0 ? 1 : 0, "");
    this.EraseClaim(i);
    if this.pendingClaims <= 0 {
      this.pendingTotal = 0;
      this.pendingDeceased = 0;
      this.dueAt = 0.0;
    };
    this.Log("claim withdrawn (" + why + ") -" + IntToString(pay) + " | batch " + IntToString(this.pendingTotal) + " eb / " + IntToString(this.pendingClaims));
    if IsDefined(s) && s.payoutMessage {
      if StrLen(line) > 0 {
        this.ReginaLine(line + " (" + IntToString(pay) + " eddies)", 5.0);
      } else {
        this.ReginaLine("You sold that one to another fixer, so I pulled the NCPD claim (" + IntToString(pay) + " eddies). One payer per perp.", 5.0);
      };
    };
  }

  private final func Payout() -> Void {
    let gi: GameInstance = this.GetGameInstance();
    let player: ref<PlayerPuppet> = GetPlayer(gi);
    let s: ref<BountyLedgerSettings> = this.Settings();
    let i: Int32 = 0;
    let ent: ref<GameObject>;
    let total: Int32;
    let claims: Int32;
    let deceased: Int32;
    let evt: ref<BountyCompletionEvent>;
    let text: String;
    let ncf: Bool;
    // Bodies still loaded: a target claimed alive that is dead now drops to the dead rate.
    while i < ArraySize(this.m_claimIDs) {
      if this.m_claimIsAlive[i] {
        ent = GameInstance.FindEntityByID(gi, this.m_claimIDs[i]) as GameObject;
        if IsDefined(ent) && ent.IsDead() {
          this.DowngradeIfClaimedAlive(this.m_claimHashes[i], "dead at payout");
        };
      };
      i += 1;
    };
    this.CustodyCheck();
    total = this.pendingTotal;
    claims = this.pendingClaims;
    deceased = this.pendingDeceased;
    this.pendingTotal = 0;
    this.pendingClaims = 0;
    this.pendingDeceased = 0;
    this.dueAt = 0.0;
    this.ClearSession();
    if total <= 0 {
      this.Log("payout skipped | batch was 0 eb / " + IntToString(claims));
      return;
    };
    this.lifetimePaid += total;
    this.lifetimeClaims += claims;
    this.lifetimeBatches += 1;
    this.lastPayoutAt = this.Now();
    this.lastPayoutAmount = total;
    this.Note(6, total, TDBID.None(), claims, "");
    ncf = CSBL_TellNCF(total);
    CSBL_TagCashflow(gi, "NCPD transfer, " + IntToString(claims) + (claims == 1 ? " claim" : " claims"));
    GameInstance.GetTransactionSystem(gi).GiveItem(player, MarketSystem.Money(), total);
    evt = new BountyCompletionEvent();
    evt.moneyAwarded = total;
    evt.streetCredAwarded = 0;
    GameInstance.GetUISystem(gi).QueueEvent(evt);
    if IsDefined(s) && s.payoutMessage {
      text = "NCPD transfer cleared, " + IntToString(total) + " eddies on your account (" + IntToString(claims) + (claims == 1 ? " claim" : " claims");
      if deceased > 0 {
        text += ", " + IntToString(deceased) + " deceased";
      };
      text += "). Pleasure doing business.";
      this.ReginaLine(text, 6.0);
    };
    this.Log("payout " + IntToString(total) + " eb | " + IntToString(claims) + " claims, " + IntToString(deceased) + " deceased | NCF " + (ncf ? "booked" : "not booked"));
  }
}

// ---------------------------------------------------------------- hooks

@addMethod(NPCPuppet)
public final func CSBL_SetBountyNow(b: Bounty) -> Void {
  this.m_bounty = b;
}

// Rule 1: the price the scanner shows and the claim uses.
@wrapMethod(BountyManager)
public final static func SetBountyFromID(bountyID: TweakDBID, target: wref<NPCPuppet>) -> Bounty {
  let bounty: Bounty = wrappedMethod(bountyID, target);
  let ledger: ref<BountyLedger>;
  let price: Int32;
  let stars: Int32;
  let generic: Bool;
  if !IsDefined(target) {
    return bounty;
  };
  ledger = BountyLedger.Get(target.GetGame());
  if !IsDefined(ledger) || !ledger.Active() {
    return bounty;
  };
  price = ledger.PriceFor(bountyID, target, stars, generic);
  if price < 0 || price == bounty.m_moneyAmount {
    return bounty;
  };
  ledger.Log("price " + TDBID.ToStringDEBUG(target.GetRecordID()) + " | " + IntToString(stars) + " stars | " + (generic ? "generic" : "named") + " | " + IntToString(bounty.m_moneyAmount) + " -> " + IntToString(price));
  bounty.m_moneyAmount = price;
  if generic {
    bounty.m_wantedStars = stars;
  };
  NPCPuppet.SetBountyObject(target, bounty);
  return bounty;
}

// Rules 2-4: file the claim, then let the vanilla chain give street cred / XP with 0 money.
@wrapMethod(BountyManager)
public final static func CompleteBounty(target: wref<NPCPuppet>) -> Void {
  let ledger: ref<BountyLedger>;
  if IsDefined(target) {
    ledger = BountyLedger.Get(target.GetGame());
    if IsDefined(ledger) && ledger.Active() {
      ledger.FileClaim(target);
    };
  };
  wrappedMethod(target);
}

// Killed or knocked out: tells CompleteBounty which; a death downgrades an alive claim.
@wrapMethod(ScriptedPuppet)
protected func RewardKiller(killer: wref<GameObject>, killType: gameKillType, isAnyDamageNonlethal: Bool) -> Void {
  let ledger: ref<BountyLedger> = BountyLedger.Get(this.GetGame());
  if IsDefined(ledger) {
    ledger.BeginNeutralize(this, killType, isAnyDamageNonlethal);
  };
  wrappedMethod(killer, killType, isAnyDamageNonlethal);
  if IsDefined(ledger) {
    ledger.EndNeutralize(this);
  };
  CSBLWarrants.OnNeutralized(this, killer, killType, isAnyDamageNonlethal);
}

// Rule 3: the scanner displayed this NPC's record.
@wrapMethod(NPCPuppet)
public const func CompileScannerChunks() -> Bool {
  let result: Bool = wrappedMethod();
  let ledger: ref<BountyLedger> = BountyLedger.Get(this.GetGame());
  if IsDefined(ledger) {
    ledger.NoteScanned(this.GetEntityID());
  };
  CSBLWarrants.OnScanned(this);
  return result;
}

// The chain's 0-money banner at claim time is hidden; the payout's banner shows.
@wrapMethod(BountyCollectedNotificationQueue)
protected cb func OnBountyCompletionEvent(evt: ref<BountyCompletionEvent>) -> Bool {
  let s: ref<BountyLedgerSettings> = BountyLedgerSettings.Get(GetGameInstance());
  if IsDefined(s) && s.enabled && IsDefined(evt) && evt.moneyAwarded <= 0 {
    return false;
  };
  return wrappedMethod(evt);
}
