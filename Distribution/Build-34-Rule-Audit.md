# Court Story Scoring Audit

Research date: 9 October 2026. Implementation and native verification are still in
progress. This is not a release certificate or a claim of physical Watch testing.

## Format Policy

Named sports expose a short catalogue of governing-body formats. They do not
expose arbitrary targets, caps or invented combinations. Custom remains numeric,
with a user-supplied sport name and configurable sides, targets and match length.
Existing record rules are value snapshots: changing future defaults never rewrites
past scores. Legacy one-set tennis records keep the existing scorer and editor.

## Primary Sources

- [ITF Rules of Tennis 2026](https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf), Rules 5-7 and Appendix VI: games and sets, advantage/no-ad, seven-point set tie-breaks and permitted deciding match tie-breaks. The current catalogue offers best of three, best of five and no-ad with a deciding ten-point match tie-break.
- [FIP Rules of Padel 2026](https://www.padelfip.com/wp-content/uploads/2025/12/FIP_Rules-of-Padel-1.pdf), Rule 1: best of three; advantage, Star Point and Golden Point are distinct choices. Star Point has two advantage opportunities before a deciding point at the third deuce. Padel's named format is doubles.
- [USA Pickleball Official Rulebook 2026](https://usapickleball.org/docs/rules/USAP-Official-Rulebook.pdf), Sections 4-6, 14, 15.C and 21.F: standard side-out scoring, the opening doubles service exception and alternating first service between games. The catalogue offers best of three/five to eleven and one game to fifteen/twenty-one, winning by two. Provisional rally-scoring rules are not presented as the ordinary default.
- [BWF statutes and Laws of Badminton](https://corporate.bwfbadminton.com/statutes/) and [BWF simplified rules](https://system.bwfbadminton.com/documents/folder_1_81/Regulations/Simplified-Rules/Simplified%20Rules%20of%20Badminton%20-%20Dec%202015.pdf): current best of three to twenty-one, win by two with thirty as the cap. The [Japan Badminton Association's implementation notice](https://www.badminton.or.jp/news/detail/2156) gives 4 January 2027 for the new fifteen-point system. That future rule must not silently replace the current format. The current full Laws endpoint blocked automated retrieval; the primary simplified rules and federation commencement notice were readable.
- [World Squash singles rules](https://worldsquashofficiating.com/rules-of-squash/), September 2025, and [WSF doubles rules published by England Squash](https://data.englandsquash.com/files?fileName=c4a12399-e40f-4a1b-b792-08a4253b235a.pdf), Rules 2 and 5: singles PAR eleven, win by two; international softball doubles eleven with a deciding point at ten-all. Best of five/three are offered. The latter must be labelled softball doubles, not represented as North American hardball doubles.
- [ITTF Statutes 2026](https://db.ittf.com/sites/default/files/public/2026-02/2026_Statutes_v1_consolidated_clean.pdf), Laws 2.11-2.15: games to eleven by two, odd-number match lengths, service in pairs of points and every point at ten-all. The catalogue offers best of three/five/seven. Doubles receiver order, the final-game change and expedite procedures require their own checks; a point-total test is not proof of these procedures.
- [IRF Indoor Racquetball Rules 2026-2028](https://www.internationalracquetball.com/wp-content/uploads/2026/06/1-irf-rulebook_mar26-1.pdf), Rules 1.4, 1.5, 3.1 and 4.1: rally scoring, best of five to eleven by two; alternating initial service in the first four games. Aggregate points decide who chooses service in game five, with another toss if level. Doubles uses the opening single-server exception, then both servers. This must not use pickleball's side-out-only points.
- [FIR Rules of Racketlon](https://www.racketlon.net/wp-content/uploads/2022/07/FIR-Rules-of-Racketlon-25.07.2022.pdf), July 2022: table tennis, badminton, squash, then tennis; each discipline to twenty-one by two. Aggregate points decide the match, not games won. A tied final aggregate requires a Gummiarm point with a new service choice and one serve. Mathematical early completion and doubles rotation are separate audit cases.
- [ITF Rules of Beach Tennis 2026](https://www.itftennis.com/media/15548/rules-of-beach-tennis-2026.pdf): no-ad games, set tie-breaks at six-all and a deciding ten-point match tie-break. Store the actual deciding point scores, not a fabricated one-zero score.
- [APTA Rules of Platform Tennis](https://platformtennis.org/rules/), Rules 6, 9 and 18: advantage doubles, no-ad singles, set tie-breaks at six-all. Tie-break service starts from the ad court, unlike ordinary tennis. Singles and doubles also differ in permitted serve attempts.

## Evidence and Remaining Checks

`CourtScoreTests` covers numeric Custom multi-side scoring, undo/reset, side-out
points, doubles opening service, badminton's cap, table tennis deuce service,
padel Star Point, legacy one-set play, deciding match tie-break points, aggregate
Gummiarm, official-format selection and invalid-score retention. New cases cover
softball doubles, between-game service and deciding-game choice.

Do not infer full service-position coverage from side-level tests. Member-level
doubles rotation, receiving order, official penalty/retirement entry, complete
phone/Watch editing journeys and every mode/notification route remain release
gates until implemented and verified. No invented player ability or sensor values.

## Apple Health Verification

[Apple's workout-session guidance](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
requires actual session startup and builder collection, then collection end and
workout save. [Authorization completion](https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:completion:))
is not a permission grant. Previously granted workout write access does not mean
all requested read types have been decided. Read denial cannot be inferred from
missing samples. Only the device owner's activity may enter their Health store.

The native Watch suite exercises one Start Workout action, grant, denial, retry,
cancelled/late callbacks and save failure through an explicit simulator-only test
client. A separate case uses real HealthKit APIs. They are different evidence.
Simulator builds need their Health capability metadata; disabling all code signing
does not establish a valid Health test. Ad-hoc simulator signing uses no private
Apple credentials. The distribution signature and physical wrist recording still
require separate verification. Timer-only success is not a Health pass.
