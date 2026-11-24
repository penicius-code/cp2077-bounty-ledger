// Cyberslop Bounty Ledger 1.1.7, warrants (2026-11-23): a flagged target killed by someone else (gang, cop, car) is
// no longer journalled as V's warrant kill ("killed, no fee"); it shows as "died (not by V)" in the NCPD Uplink.
// Cyberslop Bounty Ledger 1.1.3: Deep Scan warrants (2026-11-06; 1.1.2: a kill clears the lawful-arrest flags;
// 1.1.3: lawful arrest no longer sets the saved PS flag IsPreventionNotified, a PreventionSystem wrap
// skips the report for flagged, unkilled targets this session instead; 1.1.4: window accessors,
// journal entries)
// Kiroshi Optics - Deep Scan Protocol gives every scanned civilian a criminal record, with a warrant
// line, rebuilt from the NPC's entity hash. Until now that line was flavour. Here an active warrant
// is a job, like a bail enforcement agent's:
//   - When V's scanner reads a civilian whose record shows an active warrant, the optics flag it:
//     HUD notice with the offence and the fee (Mod Settings: star prices x warrant fee %).
//   - Bring them in alive: a non-lethal knockout by V files a claim that rides in the Ledger's next
//     NCPD batch. Killing them pays nothing and stays a murder (NCPD Duty Expansion still reports it).
//   - Lawful arrest: a flagged target that V takes down is no assault report (PreventionSystem.
//     ShouldPreventionSystemReactToAttack wrap, NCPD Duty Expansion's wasHurtAndProcessed). Witnesses still panic.
// Classes (stars): murder 5; violent crime, armed robbery, corpo extradition 4; assault, cybercrime,
// probation / parole violation, NCPD detainer 3; theft, fraud, property, drugs, weapons possession,
// bench warrant, failure to appear, material witness 2. Cleared / expired / recalled warrants pay 0.
// Gangers (NCPD bounties), police, vendors, quest and named NPCs are never warrant targets.
// The record is computed with Deep Scan's own functions (same seed recipe as its scanner), so the
// optics and the NCPD always agree. Without Deep Scan the feature is off.
module CyberslopBountyLedger

// ---------------------------------------------------------------- Deep Scan bridge

@if(ModuleExists("KiroshiDeepScan.Localization"))
func CSBL_DeepScanWarrant(npc: ref<NPCPuppet>) -> String {
  let appearance: String = NameToString(npc.GetCurrentAppearanceName());
  let recLower: String = StrLower(TDBID.ToStringDEBUG(npc.GetRecordID()));
  let gang: String;
  let h: Int32;
  let seed: Int32;
  let life: ref<KdspLifePath>;
  let arch: String;
  let age: Int32;
  let coh: ref<KdspCoherenceProfile>;
  let rec: ref<KdspCriminalRecordData>;
  // Same exclusions as Deep Scan's scanner: quest scanners, named NPCs, children, gangs, Barghest,
  // NCPD, Trauma Team (they get no generated rap sheet there either).
  if KdspQuestScannerExclusions.ShouldUseVanillaScannerPrecomputed(recLower, appearance) {
    return "";
  };
  if IsDefined(KdspUniqueNPCManager.TryGetBackstory(npc)) {
    return "";
  };
  if KdspChildBackstoryGenerator.IsChildNPC(appearance) {
    return "";
  };
  gang = KdspGangManager.DetectGangAffiliation(appearance, "");
  if !Equals(gang, "NONE") || StrContains(appearance, "barghest") || StrContains(appearance, "kurtz") {
    return "";
  };
  if KdspNCPDNameGenerator.IsNCPD(appearance) || StrContains(appearance, "trauma") {
    return "";
  };
  // KdspBackstoryManager.GenerateBackstoryUI: seed, life path, age, coherence, record.
  h = Cast<Int32>(EntityID.GetHash(npc.GetEntityID()));
  seed = RandRange(h + (KdspBackstoryManager.GetSeedVersion() * 100000), 0, 2147483647);
  life = KdspLifePath.Create(npc);
  if !IsDefined(life) {
    return "";
  };
  arch = life.archetype;
  age = CSBL_DeepScanAge(seed, arch);
  coh = KdspCoherenceManager.Generate(seed + 500, arch, age, gang);
  rec = KdspCriminalRecordManager.GenerateCoherent(seed + 1000, arch, gang, coh);
  if !IsDefined(rec) || !rec.hasRecord || Equals(rec.warrantStatus, "NONE") {
    return "";
  };
  return rec.warrantStatus;
}

// Copy of KdspBackstoryManager.GetAge (private there).
@if(ModuleExists("KiroshiDeepScan.Localization"))
func CSBL_DeepScanAge(seed: Int32, archetype: String) -> Int32 {
  if Equals(archetype, "CORPO_MANAGER") { return RandRange(seed + 8888, 35, 60); };
  if Equals(archetype, "CORPO_DRONE") { return RandRange(seed + 8888, 22, 45); };
  if Equals(archetype, "YUPPIE") { return RandRange(seed + 8888, 25, 45); };
  if Equals(archetype, "GANGER") { return RandRange(seed + 8888, 18, 35); };
  if Equals(archetype, "HOMELESS") { return RandRange(seed + 8888, 25, 65); };
  if Equals(archetype, "JUNKIE") { return RandRange(seed + 8888, 20, 50); };
  if Equals(archetype, "NOMAD") { return RandRange(seed + 8888, 20, 50); };
  return RandRange(seed + 8888, 20, 55);
}

@if(!ModuleExists("KiroshiDeepScan.Localization"))
func CSBL_DeepScanWarrant(npc: ref<NPCPuppet>) -> String {
  return "";
}

// NCPD Duty Expansion runs its own assault detection; its per-NPC "already handled" flag skips it.
@if(ModuleExists("NCPDExpansion.Config"))
func CSBL_NDEMarkHandled(npc: ref<NPCPuppet>) -> Void {
  npc.wasHurtAndProcessed = true;
}

@if(!ModuleExists("NCPDExpansion.Config"))
func CSBL_NDEMarkHandled(npc: ref<NPCPuppet>) -> Void {}

@if(ModuleExists("NCPDExpansion.Config"))
func CSBL_NDEUnmark(npc: ref<NPCPuppet>) -> Void {
  npc.wasHurtAndProcessed = false;
}

@if(!ModuleExists("NCPDExpansion.Config"))
func CSBL_NDEUnmark(npc: ref<NPCPuppet>) -> Void {}

// ---------------------------------------------------------------- warrants

public class CSBLWarrants extends ScriptableSystem {

  // This session: every NPC already checked, and the flagged warrant targets.
  private let m_seen: array<Uint32>;
  private let m_flagged: array<Uint32>;
  private let m_flaggedPay: array<Int32>;
  private let m_flaggedLabel: array<String>;
  private let m_flaggedIDs: array<EntityID>;
  private let m_flaggedStars: array<Int32>;
  private let m_served: array<Uint32>;
  private let m_killed: array<Uint32>;
  private let m_diedOther: array<Uint32>;   // 1.1.7: flagged targets killed by someone else
  // Warrant text (localized) -> class, built on first use.
  private let m_tableReady: Bool;
  private let m_text: array<String>;
  private let m_stars: array<Int32>;

  public static func Get(gi: GameInstance) -> ref<CSBLWarrants> {
    return GameInstance.GetScriptableSystemsContainer(gi).Get(n"CyberslopBountyLedger.CSBLWarrants") as CSBLWarrants;
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    ArrayClear(this.m_seen);
    ArrayClear(this.m_flagged);
    ArrayClear(this.m_flaggedPay);
    ArrayClear(this.m_flaggedLabel);
    ArrayClear(this.m_flaggedIDs);
    ArrayClear(this.m_flaggedStars);
    ArrayClear(this.m_served);
    ArrayClear(this.m_killed);
    ArrayClear(this.m_diedOther);
  }

  private final func AddClass(key: CName, stars: Int32) -> Void {
    ArrayPush(this.m_text, GetLocalizedTextByKey(key));
    ArrayPush(this.m_stars, stars);
  }

  private final func BuildTable() -> Void {
    if this.m_tableReady {
      return;
    };
    this.m_tableReady = true;
    this.AddClass(n"Kdsp-CriminalRecord-T44", 5);  // murder
    this.AddClass(n"Kdsp-CriminalRecord-T45", 4);  // violent crime
    this.AddClass(n"Kdsp-CriminalRecord-T46", 4);  // armed robbery
    this.AddClass(n"Kdsp-CriminalRecord-T47", 4);  // drug trafficking
    this.AddClass(n"Kdsp-CriminalRecord-T48", 3);  // weapons charges
    this.AddClass(n"Kdsp-CriminalRecord-T49", 2);  // bench warrant
    this.AddClass(n"Kdsp-CriminalRecord-T50", 2);  // failure to appear
    this.AddClass(n"Kdsp-CriminalRecord-T51", 3);  // probation violation
    this.AddClass(n"Kdsp-CriminalRecord-T52", 3);  // assault
    this.AddClass(n"Kdsp-CriminalRecord-T53", 2);  // property crime
    this.AddClass(n"Kdsp-CriminalRecord-T54", 2);  // drug charges
    this.AddClass(n"Kdsp-CriminalRecord-T55", 2);  // weapons possession
    this.AddClass(n"Kdsp-CriminalRecord-T56", 3);  // cybercrimes
    this.AddClass(n"Kdsp-CriminalRecord-T57", 2);  // fraud
    this.AddClass(n"Kdsp-CriminalRecord-T58", 2);  // theft
    this.AddClass(n"Kdsp-CriminalRecord-T59", 3);  // parole violation
    this.AddClass(n"Kdsp-CriminalRecord-T60", 2);  // material witness
    this.AddClass(n"Kdsp-CriminalRecord-T61", 4);  // corpo extradition request
    this.AddClass(n"Kdsp-CriminalRecord-T62", 3);  // NCPD detainer
    // T63-T66 (cleared, expired, recalled) are not in the table: class 0, no fee.
  }

  public final func StarsFor(text: String) -> Int32 {
    let i: Int32 = 0;
    this.BuildTable();
    while i < ArraySize(this.m_text) {
      if Equals(this.m_text[i], text) {
        return this.m_stars[i];
      };
      i += 1;
    };
    return 0;
  }

  // Civilians only: gangers carry NCPD bounties (the Ledger's other path).
  public final static func Eligible(npc: ref<NPCPuppet>) -> Bool {
    let b: Bounty;
    if !IsDefined(npc) || !npc.IsHuman() || npc.IsDead() || ScriptedPuppet.IsDefeated(npc) {
      return false;
    };
    if npc.IsCharacterGanger() || npc.IsCharacterPolice() || npc.IsPrevention() || npc.IsVendor() || npc.IsQuest() {
      return false;
    };
    if !npc.IsCrowd() && !npc.IsCharacterCivilian() {
      return false;
    };
    b = npc.GetBounty();
    if ArraySize(b.m_transgressions) > 0 {
      return false;
    };
    return true;
  }

  // Scanner read this NPC (NPCPuppet.CompileScannerChunks wrap in CyberslopBountyLedger.reds).
  public final static func OnScanned(npc: ref<NPCPuppet>) -> Void {
    let gi: GameInstance;
    let w: ref<CSBLWarrants>;
    let s: ref<BountyLedgerSettings>;
    let ledger: ref<BountyLedger>;
    let h: Uint32;
    let text: String;
    let stars: Int32;
    let pay: Int32;
    if !IsDefined(npc) {
      return;
    };
    gi = npc.GetGame();
    w = CSBLWarrants.Get(gi);
    s = BountyLedgerSettings.Get(gi);
    ledger = BountyLedger.Get(gi);
    if !IsDefined(w) || !IsDefined(s) || !IsDefined(ledger) || !s.enabled || !s.warrants {
      return;
    };
    h = EntityID.GetHash(npc.GetEntityID());
    if ArrayContains(w.m_seen, h) {
      return;
    };
    ArrayPush(w.m_seen, h);
    if ArraySize(w.m_seen) > 2048 {
      ArrayErase(w.m_seen, 0);
    };
    if !CSBLWarrants.Eligible(npc) {
      return;
    };
    text = CSBL_DeepScanWarrant(npc);
    if StrLen(text) == 0 {
      return;
    };
    stars = w.StarsFor(text);
    if stars <= 0 || stars < s.warrantMinStars {
      ledger.Log("warrant seen " + TDBID.ToStringDEBUG(npc.GetRecordID()) + " | " + text + " | class " + IntToString(stars) + ", not served");
      return;
    };
    pay = (s.StarPrice(stars) * s.warrantRate + 50) / 100;
    if pay <= 0 {
      return;
    };
    ArrayPush(w.m_flagged, h);
    ArrayPush(w.m_flaggedPay, pay);
    ArrayPush(w.m_flaggedLabel, text);
    ArrayPush(w.m_flaggedIDs, npc.GetEntityID());
    ArrayPush(w.m_flaggedStars, stars);
    ledger.Note(9, pay, npc.GetRecordID(), stars, text);
    if s.warrantLegalCover {
      CSBL_NDEMarkHandled(npc);
    };
    if s.warrantNotice {
      ledger.ReginaLine("NCPD has paper on this one, " + text + ". Bring them in alive: " + IntToString(pay) + " eddies.", 5.0);
    };
    ledger.Log("warrant flagged " + TDBID.ToStringDEBUG(npc.GetRecordID()) + " | " + text + " | " + IntToString(stars) + " stars | fee " + IntToString(pay) + (s.warrantLegalCover ? " | lawful arrest" : ""));
  }

  // Knocked out or killed (ScriptedPuppet.RewardKiller wrap in CyberslopBountyLedger.reds).
  public final static func OnNeutralized(puppet: ref<ScriptedPuppet>, killer: wref<GameObject>, killType: gameKillType, nonlethal: Bool) -> Void {
    let npc: ref<NPCPuppet> = puppet as NPCPuppet;
    let gi: GameInstance;
    let w: ref<CSBLWarrants>;
    let ledger: ref<BountyLedger>;
    let h: Uint32;
    let i: Int32;
    if !IsDefined(npc) {
      return;
    };
    gi = npc.GetGame();
    w = CSBLWarrants.Get(gi);
    ledger = BountyLedger.Get(gi);
    if !IsDefined(w) || !IsDefined(ledger) || ArraySize(w.m_flagged) == 0 {
      return;
    };
    h = EntityID.GetHash(npc.GetEntityID());
    i = ArrayFindFirst(w.m_flagged, h);
    if i < 0 {
      return;
    };
    // A kill is a killing, warrant or not (also finishing a target already brought down):
    // drop the lawful-arrest flags now, inside RewardKiller, before vanilla's
    // CheckIfPreventionShouldReact reports the death (GameObject.FindAndRewardKiller).
    if Equals(killType, gameKillType.Normal) || npc.IsDead() {
      // 1.1.2 set the saved PS flag at scan time; clear it on saves that still carry it.
      npc.GetPuppetPS().SetIsPreventionNotified(false);
      CSBL_NDEUnmark(npc);
      // 1.1.7: only V's kills go in the journal as a warrant killing
      if !IsDefined(killer) || !killer.IsPlayer() {
        if !ArrayContains(w.m_diedOther, h) {
          ArrayPush(w.m_diedOther, h);
        };
        ledger.Log("warrant target died, not by V: " + TDBID.ToStringDEBUG(npc.GetRecordID()) + " | " + w.m_flaggedLabel[i] + " | no claim");
        return;
      };
      if !ArrayContains(w.m_killed, h) {
        ArrayPush(w.m_killed, h);
        ledger.Note(10, 0, npc.GetRecordID(), w.m_flaggedStars[i], w.m_flaggedLabel[i]);
      };
      if !ArrayContains(w.m_served, h) {
        ArrayPush(w.m_served, h);
      };
      ledger.Log("warrant target killed " + TDBID.ToStringDEBUG(npc.GetRecordID()) + " | " + w.m_flaggedLabel[i] + " | no fee (alive only), reported as a killing");
      return;
    };
    if ArrayContains(w.m_served, h) || !IsDefined(killer) || !killer.IsPlayer() {
      return;
    };
    if Equals(killType, gameKillType.Defeat) && nonlethal {
      if ledger.FileWarrantClaim(npc, w.m_flaggedPay[i], w.m_flaggedLabel[i], w.m_flaggedStars[i]) {
        ArrayPush(w.m_served, h);
      };
    };
  }

  // Lawful arrest: V's hits on a flagged warrant target, alive, are not reported to NCPD. Session
  // only (m_flagged is not saved), nothing is written on the NPC; a killing is reported as usual.
  public final static func LawfulArrest(target: wref<GameObject>) -> Bool {
    let npc: ref<NPCPuppet> = target as NPCPuppet;
    let w: ref<CSBLWarrants>;
    let s: ref<BountyLedgerSettings>;
    let h: Uint32;
    if !IsDefined(npc) || npc.IsDead() {
      return false;
    };
    w = CSBLWarrants.Get(npc.GetGame());
    if !IsDefined(w) || ArraySize(w.m_flagged) == 0 {
      return false;
    };
    s = BountyLedgerSettings.Get(npc.GetGame());
    if !IsDefined(s) || !s.enabled || !s.warrants || !s.warrantLegalCover {
      return false;
    };
    h = EntityID.GetHash(npc.GetEntityID());
    return ArrayContains(w.m_flagged, h) && !ArrayContains(w.m_killed, h);
  }

  // For the Biomonitor and NCPD Uplink windows / console.
  public final func FlaggedCount() -> Int32 = ArraySize(this.m_flagged)
  public final func ServedCount() -> Int32 = ArraySize(this.m_served)
  public final func FlaggedLabel(i: Int32) -> String {
    if i < 0 || i >= ArraySize(this.m_flaggedLabel) { return ""; };
    return this.m_flaggedLabel[i];
  }
  public final func FlaggedPay(i: Int32) -> Int32 {
    if i < 0 || i >= ArraySize(this.m_flaggedPay) { return 0; };
    return this.m_flaggedPay[i];
  }
  public final func FlaggedStars(i: Int32) -> Int32 {
    if i < 0 || i >= ArraySize(this.m_flaggedStars) { return 0; };
    return this.m_flaggedStars[i];
  }
  // 0 open, 1 served (claim filed), 2 killed by V, 3 died, not by V (1.1.7).
  public final func FlaggedState(i: Int32) -> Int32 {
    if i < 0 || i >= ArraySize(this.m_flagged) { return 0; };
    if ArrayContains(this.m_diedOther, this.m_flagged[i]) { return 3; };
    if ArrayContains(this.m_killed, this.m_flagged[i]) { return 2; };
    if ArrayContains(this.m_served, this.m_flagged[i]) { return 1; };
    return 0;
  }
  // -1 = not loaded, else metres from V.
  public final func FlaggedDistance(i: Int32) -> Float {
    let ent: ref<GameObject>;
    let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
    if i < 0 || i >= ArraySize(this.m_flaggedIDs) || !IsDefined(player) { return -1.0; };
    ent = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_flaggedIDs[i]) as GameObject;
    if !IsDefined(ent) { return -1.0; };
    return Vector4.Distance(ent.GetWorldPosition(), player.GetWorldPosition());
  }
}

@wrapMethod(PreventionSystem)
public final static func ShouldPreventionSystemReactToAttack(target: wref<GameObject>, attackTime: Float, istargetDefeated: Bool) -> Bool {
  if CSBLWarrants.LawfulArrest(target) {
    return false;
  };
  return wrappedMethod(target, attackTime, istargetDefeated);
}
