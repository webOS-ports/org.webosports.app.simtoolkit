# SIM Toolkit

`org.webosports.app.simtoolkit` shows the SIM card's own menu: the
applications operators put on the SIM, such as the balance, top-up and
operator services. While one of these applications runs, the app shows what
it asks. That can be a choice from a list, a message, some text or digits to
type (hidden for codes), a single key, a yes/no question, or a request to
make a call, open a web page or open a data connection. Tones are shown as
a notice and not played.

The app only handles the screen. webos-telephonyd talks to the SIM card:
it registers the ofono SIM toolkit agent and offers these luna methods on
`com.webos.service.telephony` (and `com.palm.telephony`):

| method | |
|---|---|
| `stkGetMainMenu {simId?, subscribe?}` | the menu: `{available, title, items: [{index, label, iconId}], idleModeText, simId}` |
| `stkSelectItem {simId?, index}` | start the application behind a menu entry |
| `stkAgentRequest {subscribe: true}` | the pending requests, then `{event: "request", request}` and `{event: "ended", ended: {requestId, reason}}` |
| `stkRespond {requestId, action?, value?}` | `action`: `answer` (default), `goBack`, `endSession`, `busy` or `cancel` |

If the SIM card asks something while the app is closed, telephonyd starts
it. If the app cannot be started, telephonyd posts a toast that opens it.
With a telephonyd that has no SIM toolkit support, the app says so.

The back gesture (Escape) answers "back" where the SIM card allows it.
Otherwise it ends the session. The few requests that allow neither are
declined.

## Permissions

`requiredPermissions` in `appinfo.json`:

- `telephony.management` for the four methods
- `application.launcher` and `appmanager.management` to open a web page
  the SIM card offers, once the user agrees

## Tests

```sh
tools/run-tests.sh [path to luneos-components]
```

This runs `tests/qml/tst_logic.qml`, which covers `qml/js/Stk.js`: views,
answer checks and the back gesture. It also runs `tests/qml/tst_ui.qml`,
which starts the app with `tests/qml/FakeStkBus.qml` standing in for
telephonyd and covers every request type. Both run with qmltestrunner and
luneos-components' desktop build.

`tools/mutation-check.sh` breaks the code in 19 ways, one at a time, and
checks that the tests catch each one.

## Install for development

```sh
tools/install.sh <adb serial>
```

This builds an ipk (Architecture: all, since the app is QML only) and
installs it through `com.webos.appInstallService`.

`tools/make-icon.sh` renders `images/icon.svg` into the PNG icons.

## Licence

GNU General Public License version 3; see LICENSE.
