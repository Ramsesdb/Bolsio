enum AttachmentOwnerType {
  transaction,
  userProfile,
  account,
  budget;

  String get dbValue {
    switch (this) {
      case AttachmentOwnerType.transaction:
        return 'transaction';
      case AttachmentOwnerType.userProfile:
        return 'userProfile';
      case AttachmentOwnerType.account:
        return 'account';
      case AttachmentOwnerType.budget:
        return 'budget';
    }
  }

  static AttachmentOwnerType fromDbValue(String value) {
    switch (value) {
      case 'transaction':
        return AttachmentOwnerType.transaction;
      case 'userProfile':
        return AttachmentOwnerType.userProfile;
      case 'account':
        return AttachmentOwnerType.account;
      case 'budget':
        return AttachmentOwnerType.budget;
      default:
        throw ArgumentError('Unknown AttachmentOwnerType dbValue: $value');
    }
  }
}

class Attachment {
  const Attachment({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.localPath,
    required this.mimeType,
    required this.sizeBytes,
    this.role,
    required this.createdAt,
  });

  final String id;
  final AttachmentOwnerType ownerType;
  final String ownerId;
  final String localPath;
  final String mimeType;
  final int sizeBytes;
  final String? role;
  final DateTime createdAt;
}
