# PUSHKA 1.0.1 (5) — review response

We have made functional changes following the rejection of 1.0.0 (4), rather than resubmitting the same binary. The new version is 1.0.1 (5).

1. Purpose and problem solved
PUSHKA is an owner-operated classifieds board for direct, locally arranged transactions. A person publishes an individual item, another person searches by city, category, condition and price, and contacts its author. It does not process a retail checkout. In 1.0.1 we added a private inspection workflow: save up to ten listing snapshots, compare two or three candidates, record six inspection checks and private notes before meeting the author. A personal item can also be entered manually without publishing an ad or creating an account.

2. Intended users
Adults in Kazakhstan buying or selling individual items and arranging the inspection or handover themselves. Russian and Kazakh interfaces are included. The notebook is intended for a buyer comparing actual condition, completeness, operation, provenance, agreed price and meeting arrangements before paying.

3. Specific product value
The new workflow connects listing discovery with the buyer's own physical inspection, rather than adding another retail storefront. A listing snapshot retains its quoted price, city and condition; a side-by-side worksheet combines these with the buyer's checks and notes. It works without login and does not transmit the notes to a seller or our backend. We do not claim these individual concepts are exclusive to PUSHKA or that a checklist guarantees a safe transaction. The UI explains that snapshots may become outdated and conditions must be reconfirmed with the author.

4. Testing and feedback
The owner confirms that real testing took place. We do not have a documented TestFlight cohort, dated feedback report or specific tester quotations to provide, and do not attribute developer changes to undocumented user feedback. Verifiable technical testing for this build includes 15 automated tests, covering guest access, notebook persistence, duplicate handling, selecting two items for comparison, editing inspection checks and notes, manual item entry without publishing an ad, and existing app behavior. Static analysis passes. These are developer QA results, not a claim of independent user research.

5. Relationship with other apps
PUSHKA is a standalone product owned by the account holder. BazarKz, also owned by the account holder, is a retailer marketplace/internet store with buyer and seller applications and store/catalog/cart workflows. PUSHKA has its own branding, Firebase project, content and account namespace and uses an individual-classified listing/contact/inspection workflow. It is not a BazarKz companion or an alternative skin for the same store.

6. Consolidation
The two workflows could technically be placed in one application, but the owner chose separate products for different transactions: retailer catalog shopping in BazarKz and locally arranged individual classifieds in PUSHKA. PUSHKA does not unlock BazarKz content or paid features, and its inspection notebook is available without a store account. We recognize that product separation alone is not sufficient under 4.3; 1.0.1 therefore adds the functional inspection and comparison workflow described above.

7. Shared components with our other apps
Both products use standard Flutter/Dart and Firebase ecosystem components. A SHA-256 comparison of the local PUSHKA and BazarKz buyer `lib` and `assets` trees found no byte-identical file contents. Their application structures differ: PUSHKA uses its own classifieds implementation and the new inspection notebook; BazarKz uses its separate store application. This comparison is not a claim that semantically equivalent generic code cannot exist or an audit of every other binary in the account.

8. Third-party code or templates
PUSHKA depends on standard published Flutter/Firebase SDKs and plugins, including image/file selection, local preferences and URL launching. Its classifieds and inspection screens are maintained in this project's source. No commercial third-party application template or third-party content catalog has been identified in the inspected PUSHKA source. The notebook and comparison flow is application code, not a hosted website or a third-party app embedded in a WebView.

9. Ownership and submission
The account holder confirms that PUSHKA belongs to them. It is not a client-branded application being submitted by a template service on behalf of a separate content provider. This submission is under the product owner's developer account.

Review navigation
Home → “Мой блокнот осмотров” → “Добавить вещь вручную”. Add two personal items, select their checkboxes and open “Сравнить выбранные”. “Осмотр и заметки” opens the six-step worksheet. Save and reopen to verify persistence. A public listing also has “Подготовить осмотр и сравнить”. These actions do not publish sample ads. The existing supplied reviewer account remains available for authenticated consumer features. No SMS or payment is required. Ordinary account access is device-bound and uses an on-screen code, with unverified phone ownership, as disclosed in the app and metadata. Paid promotions remain disabled.
