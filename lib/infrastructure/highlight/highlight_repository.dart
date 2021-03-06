import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:kt_dart/kt.dart';
import 'package:rxdart/rxdart.dart';

import 'package:highlights/domain/highlights/value_objects.dart';
import 'package:highlights/domain/highlights/image.dart';
import 'package:highlights/domain/authentication/i_auth_facade.dart';
import 'package:highlights/infrastructure/highlight/highlight_dtos.dart';
import 'package:highlights/domain/highlights/highlight_search_filter.dart';
import 'package:highlights/domain/highlights/highlight_failure.dart';
import 'package:highlights/domain/highlights/highlight.dart';
import 'package:highlights/domain/highlights/i_highlight_repository.dart';
import 'package:highlights/infrastructure/core/firestore_helpers.dart';
import 'package:highlights/infrastructure/core/storage_helpers.dart';

// TODO: split in two repositories (Firestore (or generic docs DB)
// and Storage (generic assets DB))
@LazySingleton(as: IHighlightRepository)
class HighlightRepository implements IHighlightRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final IAuthFacade _authFacade;

  HighlightRepository(
    this._firestore,
    this._storage,
    this._authFacade,
  );

  @override
  Stream<Either<HighlightFailure, KtList<Highlight>>> watchAll() async* {
    final userDocument = await _firestore.userDocument(_authFacade);

    yield* userDocument.highlightCollection
        .orderBy('serverTimestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => right<HighlightFailure, KtList<Highlight>>(
            snapshot.docs
                .map((doc) => HighlightDto.fromFirestore(doc).toDomain())
                .toImmutableList(),
          ),
        )
        .onErrorReturnWith((e) {
      // Extension method from RxDart library to handle errors in Streams
      // TODO: consider replacing it with native error handling to remove rxdart
      // as is being used only here
      if (e is FirebaseException && e.message.contains('PERMISSION_DENIED')) {
        // TODO: test
        return left(const HighlightFailure.insufficientPermission());
      } else {
        // TODO: log e
        return left(HighlightFailure.unexpected(
          details:
              'Error while calling HighlightRepository.watchAll() in ${userDocument.toString()}',
        ));
      }
    });
  }

  // TODO: implement Algolia or Elasticsearch for better UX
  @override
  Stream<Either<HighlightFailure, KtList<Highlight>>> watchFiltered(
    HighlightSearchFilter filter,
  ) async* {
    final userDocument = await _firestore.userDocument(_authFacade);

    final collecitonRef = userDocument.highlightCollection;

    Query query = collecitonRef.orderBy('serverTimestamp', descending: true);

    if (filter.showOnlyIfHasImage) {
      query = collecitonRef.where('image.url', isNotEqualTo: '');
    }

    yield* query
        .snapshots()
        .map(
          (snapshot) => right<HighlightFailure, KtList<Highlight>>(
            snapshot.docs
                .map((doc) => HighlightDto.fromFirestore(doc).toDomain())
                .toImmutableList(),
          ),
        )
        .onErrorReturnWith((e) {
      if (e is FirebaseException && e.message.contains('PERMISSION_DENIED')) {
        // TODO: test
        return left(const HighlightFailure.insufficientPermission());
      } else {
        // TODO: log e
        return left(HighlightFailure.unexpected(
          details:
              'Error while calling HighlightRepository.watchFiltered() in ${userDocument.toString()}/$collecitonRef with ${filter.toString()}',
        ));
      }
    });
  }

  @override
  Future<Either<HighlightFailure, Unit>> create(Highlight highlight) async {
    try {
      final userDocument = await _firestore.userDocument(_authFacade);
      // TODO: refactor
      Image image;
      await highlight.image.fold(
        () {},
        (prevImage) async {
          if (prevImage.isUploaded) {
            image = prevImage;
          } else {
            final failureOrString =
                await _storage.uploadImage(highlight, userDocument);
            failureOrString.fold(
              (failure) {
                return left(failure);
              },
              (downloadUrl) {
                image = prevImage.copyWith(
                  imageUrl: some(ImageUrl(downloadUrl)),
                );
              },
            );
          }
        },
      );
      final highlightDto = HighlightDto.fromDomain(
        highlight.copyWith(image: optionOf(image)),
      );
      await userDocument.highlightCollection
          .doc(highlightDto.id)
          .set(highlightDto.toJson());
      return right(unit);
    } on FirebaseException catch (e) {
      if (e.message.contains('PERMISSION_DENIED')) {
        // TODO: test
        return left(const HighlightFailure.insufficientPermission());
      } else {
        // TODO: test
        return left(HighlightFailure.unexpected(
          details:
              'Error while calling HighlightRepository.create() with ${highlight.toString()}: ${e.toString()}',
        ));
      }
    }
  }

  @override
  Future<Either<HighlightFailure, Unit>> update(Highlight highlight) async {
    try {
      final userDocument = await _firestore.userDocument(_authFacade);
      // TODO: refactor
      Image image;
      await highlight.image.fold(
        () {},
        (prevImage) async {
          if (prevImage.isUploaded) {
            image = prevImage;
          } else {
            final failureOrString =
                await _storage.uploadImage(highlight, userDocument);
            failureOrString.fold(
              (failure) {
                return left(failure);
              },
              (downloadUrl) {
                image = prevImage.copyWith(
                  imageUrl: some(ImageUrl(downloadUrl)),
                );
              },
            );
          }
        },
      );
      final highlightDto = HighlightDto.fromDomain(
        highlight.copyWith(image: optionOf(image)),
      );
      await userDocument.highlightCollection
          .doc(highlightDto.id)
          .update(highlightDto.toJson());
      return right(unit);
    } on FirebaseException catch (e) {
      if (e.message.contains('PERMISSION_DENIED')) {
        // TODO: test
        return left(const HighlightFailure.insufficientPermission());
      } else if (e.code.contains('not-found')) {
        return left(const HighlightFailure.unableToUpdate());
      } else {
        // TODO: test
        return left(HighlightFailure.unexpected(
          details:
              'Error while calling HighlightRepository.update() with ${highlight.toString()}: ${e.toString()}',
        ));
      }
    }
  }

  @override
  Future<Either<HighlightFailure, Unit>> delete(Highlight highlight) async {
    try {
      final userDocument = await _firestore.userDocument(_authFacade);
      final highlightId = highlight.id.getOrCrash();
      await userDocument.highlightCollection.doc(highlightId).delete();
      // TODO: test
      if (highlight.image.isSome()) {
        final failureOrUnit = await deleteImage(highlight, userDocument);
        failureOrUnit.fold(
          (failure) {
            return left(failure);
          },
          (_) {},
        );
      }
      return right(unit);
    } on FirebaseException catch (e) {
      if (e.message.contains('PERMISSION_DENIED')) {
        // TODO: test
        return left(const HighlightFailure.insufficientPermission());
      } else if (e.code.contains('not-found')) {
        return left(const HighlightFailure.unableToUpdate());
      } else {
        return left(HighlightFailure.unexpected(
          details:
              'Error while calling HighlightRepository.delete() with ${highlight.toString()}: ${e.toString()}',
        ));
      }
    }
  }

  @override
  Future<Either<HighlightFailure, Unit>> deleteImage(
    Highlight highlight, [
    DocumentReference document,
  ]) async {
    try {
      final userDocument =
          document ?? await _firestore.userDocument(_authFacade);
      final storageReference = _storage.getReference(userDocument, highlight);
      await storageReference.delete();
      return right(unit);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return left(const HighlightFailure.insufficientPermission());
      } else if (e.code.contains('not-found')) {
        return left(const HighlightFailure.unableToUpdate());
      } else {
        return left(HighlightFailure.unexpected(
          details:
              'Error while calling HighlightRepository.deleteImage() ${highlight.toString()}: ${e.toString()}',
        ));
      }
    }
  }
}
