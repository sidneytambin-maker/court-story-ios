# Tennis Tracker Accessibility Standard

Tennis Tracker uses the same product language on iPhone and Apple Watch. Primary actions are `Track Tennis Activity`, `Track Training Session`, `Record Match`, `Track Tournament`, `Record Point for Sidney`, `Save Match Progress`, `Resume Match Scoring`, `Finish Match`, `Finish Training Session`, `Complete Match Details`, `Add Match to Tournament`, `Edit Match`, `Delete Match`, and `Mark Complete`.

Screens begin with a meaningful heading, then the primary action, then saved records. Headings are used for navigation, not decoration. Static summaries are grouped when that reduces swipes; interactive controls remain separate.

Rows open on double tap. Rotor actions are reserved for useful secondary actions such as edit, delete, add to Calendar, resume scoring, and complete details. Destructive actions always use a confirmation with a clear `Cancel`.

Finite choices use native pickers or menus instead of repeated increment buttons wherever practical. Normal tennis scheduling uses five-minute time increments. Training duration uses hours and finite minute choices. Watch live training calculates duration from start to finish and leaves refinement to iPhone.

Match summaries come from the shared summary formatter. Result/status comes first, then opponent or team, score, tournament, and date. Watch uses the short variant; iPhone detail and accessibility labels may use the long variant.

Score announcements use shared phrasing across devices and do not intentionally move VoiceOver focus away from the scoring button after a point is recorded.
