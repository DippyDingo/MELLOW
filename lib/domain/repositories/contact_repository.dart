import 'package:mellow/domain/entities/contact.dart';

/// Persistence contract for people.
abstract interface class ContactRepository {
  /// Watches contacts: favourites first, then alphabetically by name.
  Stream<List<Contact>> watchContacts();

  /// Case-insensitive search over name and every address.
  Future<List<Contact>> search(String query);

  Future<Contact?> getContact(String id);

  /// Finds the contact owning [email] (addresses are globally unique).
  Future<Contact?> findByEmail(String email);

  Future<Contact> saveContact(Contact contact);

  /// Attaches [email] to [contactId]; no-op when the address already exists.
  Future<void> addAddress(String contactId, ContactEmail email);

  /// Detaches [email] from its contact. History is not deleted.
  Future<void> removeAddress(String email);

  Future<void> setFavorite(String contactId, {required bool isFavorite});

  /// Merges [sourceId] into [targetId] at the user's explicit request:
  /// addresses move to the target, threads are re-pointed, source is deleted.
  Future<void> mergeContacts({required String targetId, required String sourceId});

  Future<void> deleteContact(String id);
}
