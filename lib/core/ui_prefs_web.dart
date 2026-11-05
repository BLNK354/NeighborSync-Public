/// Web: saves the preferences in localStorage so they survive closing the tab.
library;

import 'package:web/web.dart' as web;

const _sidebarKey = 'ns_sidebar_collapsed';
const _storageNoticeKey = 'ns_storage_notice_seen';

bool readSidebarCollapsed() =>
    web.window.localStorage.getItem(_sidebarKey) == 'true';

void writeSidebarCollapsed(bool value) {
  if (value) {
    web.window.localStorage.setItem(_sidebarKey, 'true');
  } else {
    web.window.localStorage.removeItem(_sidebarKey);
  }
}

/// Whether this browser has already been shown the storage notice.
/// Kept per browser (not per account) so it works before sign-in.
bool readStorageNoticeSeen() =>
    web.window.localStorage.getItem(_storageNoticeKey) == 'true';

void writeStorageNoticeSeen() =>
    web.window.localStorage.setItem(_storageNoticeKey, 'true');

/// Reloads the page, used when another tab signs in as a different person.
void reloadPage() => web.window.location.reload();
