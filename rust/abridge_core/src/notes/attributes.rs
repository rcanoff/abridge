//! Scalar attributes from Apple's Notes model.
//!
//! Source: `/System/Library/PrivateFrameworks/NotesShared.framework/Versions/A/Resources/NoteData.mom`
//! (`NSManagedObjectModel` `attributesByName`). Binary and transformable attributes are omitted.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ScalarKind {
  Integer,
  Double,
  String,
  Bool,
  Date,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ScalarAttr {
  pub name: &'static str,
  pub kind: ScalarKind,
}

macro_rules! attr {
  ($name:literal, $kind:ident) => {
    $crate::notes::attributes::ScalarAttr {
      name: $name,
      kind: $crate::notes::attributes::ScalarKind::$kind,
    }
  };
}

pub(crate) use attr;

pub(crate) const ACCOUNT: &[ScalarAttr] = &[
  attr!("accountNameForAccountListSorting", String),
  attr!("accountType", Integer),
  attr!("cryptoIterationCount", Integer),
  attr!("dateHeadersType", Integer),
  attr!("didChooseToMigrate", Bool),
  attr!("didFinishMigration", Bool),
  attr!("didMigrateOnMac", Bool),
  attr!("hasMissingKeychainItem", Bool),
  attr!("identifier", String),
  attr!("isPasswordProtected", Bool),
  attr!("isRecoveringFromTrash", Bool),
  attr!("isShareDirty", Bool),
  attr!("lastSyncDate", Date),
  attr!("markedForDeletion", Bool),
  attr!("minimumSupportedNotesVersion", Integer),
  attr!("name", String),
  attr!("needsInitialFetchFromCloud", Bool),
  attr!("needsToBeFetchedFromCloud", Bool),
  attr!("needsToFetchUserSpecificRecordAssets", Bool),
  attr!("needsToSaveUserSpecificRecord", Bool),
  attr!("needsToUpdateUserSpecificRecordReferenceActions", Bool),
  attr!("nestedTitleForSorting", String),
  attr!("originalCloudIdentifier", String),
  attr!("passwordHint", String),
  attr!("serverSideUpdateTaskFailureCount", Integer),
  attr!("serverSideUpdateTaskLastAttemptedBuild", String),
  attr!("serverSideUpdateTaskLastAttemptedVersion", String),
  attr!("serverSideUpdateTaskLastCompletedBuild", String),
  attr!("serverSideUpdateTaskLastCompletedVersion", String),
  attr!("sortOrder", Integer),
  attr!("storeDataSeparately", Bool),
  attr!("userRecordName", String),
  attr!("zoneOwnerName", String),
];
pub(crate) const FOLDER: &[ScalarAttr] = &[
  attr!("accountNameForAccountListSorting", String),
  attr!("cryptoIterationCount", Integer),
  attr!("customNoteSortTypeModificationDate", Date),
  attr!("customNoteSortTypeValue", Integer),
  attr!("dateForLastTitleModification", Date),
  attr!("dateHeadersType", Integer),
  attr!("folderType", Integer),
  attr!("hasMissingKeychainItem", Bool),
  attr!("identifier", String),
  attr!("importedFromLegacy", Bool),
  attr!("isPasswordProtected", Bool),
  attr!("isRecoveringFromTrash", Bool),
  attr!("isShareDirty", Bool),
  attr!("markedForDeletion", Bool),
  attr!("minimumSupportedNotesVersion", Integer),
  attr!("needsInitialFetchFromCloud", Bool),
  attr!("needsToBeFetchedFromCloud", Bool),
  attr!("needsToFetchUserSpecificRecordAssets", Bool),
  attr!("needsToSaveUserSpecificRecord", Bool),
  attr!("needsToUpdateUserSpecificRecordReferenceActions", Bool),
  attr!("nestedTitleForSorting", String),
  attr!("originalCloudIdentifier", String),
  attr!("parentModificationDate", Date),
  attr!("passwordHint", String),
  attr!("smartFolderQueryJSON", String),
  attr!("sortOrder", Integer),
  attr!("title", String),
  attr!("zoneOwnerName", String),
];
pub(crate) const MEDIA: &[ScalarAttr] = &[
  attr!("cryptoIterationCount", Integer),
  attr!("filename", String),
  attr!("generation", String),
  attr!("hasMissingKeychainItem", Bool),
  attr!("identifier", String),
  attr!("isPasswordProtected", Bool),
  attr!("isRecoveringFromTrash", Bool),
  attr!("isShareDirty", Bool),
  attr!("markedForDeletion", Bool),
  attr!("minimumSupportedNotesVersion", Integer),
  attr!("needsInitialFetchFromCloud", Bool),
  attr!("needsToBeFetchedFromCloud", Bool),
  attr!("needsToFetchUserSpecificRecordAssets", Bool),
  attr!("needsToSaveUserSpecificRecord", Bool),
  attr!("needsToUpdateUserSpecificRecordReferenceActions", Bool),
  attr!("originalCloudIdentifier", String),
  attr!("passwordHint", String),
  attr!("zoneOwnerName", String),
];

pub(crate) const INLINE_ATTACHMENT: &[ScalarAttr] = &[
  attr!("altText", String),
  attr!("creationDate", Date),
  attr!("cryptoIterationCount", Integer),
  attr!("hasMissingKeychainItem", Bool),
  attr!("identifier", String),
  attr!("isPasswordProtected", Bool),
  attr!("isRecoveringFromTrash", Bool),
  attr!("isShareDirty", Bool),
  attr!("markedForDeletion", Bool),
  attr!("mentionNotificationAttemptCount", Integer),
  attr!("mentionNotificationState", Integer),
  attr!("minimumSupportedNotesVersion", Integer),
  attr!("needsInitialFetchFromCloud", Bool),
  attr!("needsToBeFetchedFromCloud", Bool),
  attr!("needsToFetchUserSpecificRecordAssets", Bool),
  attr!("needsToSaveUserSpecificRecord", Bool),
  attr!("needsToUpdateUserSpecificRecordReferenceActions", Bool),
  attr!("originalCloudIdentifier", String),
  attr!("passwordHint", String),
  attr!("tokenContentIdentifier", String),
  attr!("typeUTI", String),
  attr!("zoneOwnerName", String),
];

pub(crate) fn attributes_for(entity: &str) -> &'static [ScalarAttr] {
  match entity {
    "ICAccount" => ACCOUNT,
    "ICFolder" => FOLDER,
    "ICNote" => super::note_attributes::NOTE,
    "ICAttachment" => super::note_attributes::ATTACHMENT,
    "ICInlineAttachment" => INLINE_ATTACHMENT,
    "ICMedia" => MEDIA,
    _ => &[],
  }
}
