//! Fixed Notes JXA. User input is passed only as JSON on stdin.

/// Error text the script raises when a delete targets a note already in Recently Deleted, where
/// Notes' delete would erase it for good. Sent in the request so script and mapper share it.
pub(crate) const NOTE_IN_RECENTLY_DELETED: &str = "ABRIDGE_NOTE_IN_RECENTLY_DELETED";

/// The live note is newer, or its attachment count differs, from the snapshot just read.
pub(crate) const NOTE_CHANGED: &str = "ABRIDGE_NOTE_CHANGED";

/// The live folder gained a note or subfolder after the snapshot said it was empty.
pub(crate) const FOLDER_NOT_EMPTY: &str = "ABRIDGE_FOLDER_NOT_EMPTY";

pub(crate) const JXA_SCRIPT: &str = r#"function run(argv) {
  var request = JSON.parse(readRequest(argv));
  var app = Application('Notes');
  var id;
  if (request.action === 'create_note') {
    var folder = app.folders.byId(request.folder_id);
    var created = app.make({new: 'note', withProperties: {body: request.body}, at: folder});
    id = created.id();
  } else if (request.action === 'update_note') {
    var note = app.notes.byId(request.note_id);
    var live = note.modificationDate();
    var liveMs = (live && live.getTime) ? live.getTime() : NaN;
    // A couple of seconds covers Notes' date resolution. A newer live note, or a different
    // attachment count, means someone edited it after the snapshot. Refuse before writing.
    if (typeof request.modification_ms !== 'number' || !(liveMs <= request.modification_ms + 2000)) {
      throw new Error(request.note_changed_error);
    }
    if (elementCount(note.attachments) !== request.attachment_count) {
      throw new Error(request.note_changed_error);
    }
    note.body = request.body;
    id = note.id();
  } else if (request.action === 'move_note') {
    var moving = app.notes.byId(request.note_id);
    var destination = app.folders.byId(request.folder_id);
    app.move(moving, {to: destination});
    id = moving.id();
  } else if (request.action === 'delete_note') {
    var deleting = app.notes.byId(request.note_id);
    // Checked here, at the moment of deletion: a note already in Recently Deleted would be
    // erased for good, whoever moved it there since the caller last read the store.
    if (request.trash_folder_ids.indexOf(deleting.container().id()) !== -1) {
      throw new Error(request.in_trash_error);
    }
    app.delete(deleting);
    // Notes defers saving a scripted delete. Moving the note onto the folder it now sits in
    // (Recently Deleted) changes nothing and runs Notes' move path, which saves at once.
    try { app.move(deleting, {to: deleting.container()}); } catch (error) {}
    id = deleting.id();
  } else if (request.action === 'create_folder') {
    var made;
    if (request.parent_id) {
      var parent = app.folders.byId(request.parent_id);
      made = app.make({new: 'folder', withProperties: {name: request.name}, at: parent});
    } else {
      var account = app.accounts.byId(request.account_id);
      made = app.make({new: 'folder', withProperties: {name: request.name}, at: account});
    }
    id = made.id();
  } else if (request.action === 'delete_folder') {
    // An empty-folder delete stays in memory until Notes saves. save() is that path.
    // -1728 / "Can't get object" means Notes already dropped the folder and has not saved.
    var alreadyGone = false;
    try {
      var folder = app.folders.byId(request.folder_id);
      if (elementCount(folder.notes) > 0 || elementCount(folder.folders) > 0) {
        throw new Error(request.folder_not_empty_error);
      }
      app.delete(folder);
    } catch (error) {
      var text = String(error);
      if (request.folder_not_empty_error && text.indexOf(request.folder_not_empty_error) !== -1) {
        throw error;
      }
      if (text.indexOf('-1728') === -1 && text.indexOf('Can\'t get object') === -1) {
        throw error;
      }
      alreadyGone = true;
    }
    try { app.save(); } catch (error) {}
    return JSON.stringify({id: request.folder_id, gone: true, already_gone: alreadyGone});
  } else {
    throw new Error('unknown notes action');
  }
  return JSON.stringify({id: id});
}

function readRequest(argv) {
  if (argv !== undefined && argv.length > 0 && argv[0]) {
    return argv[0];
  }
  ObjC.import('Foundation');
  var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
  if (!data || data.isNil() || data.length === 0) {
    throw new Error('empty notes request');
  }
  var text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
  if (!text || text.isNil()) {
    throw new Error('notes request is not UTF-8');
  }
  return text.js;
}

function elementCount(elements) {
  var items = elements();
  if (typeof items.length !== 'number') {
    throw new Error('missing notes collection');
  }
  return items.length;
}
"#;
