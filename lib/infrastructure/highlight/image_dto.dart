import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:highlights/domain/highlights/image.dart';
import 'package:highlights/domain/highlights/value_objects.dart';

part 'image_dto.freezed.dart';
part 'image_dto.g.dart';

@freezed
abstract class ImageDto implements _$ImageDto {
  const ImageDto._();

  const factory ImageDto({
    @required String imageUrl,
    @required String imageFile,
  }) = _ImageDto;

  factory ImageDto.fromDomain(Image image) {
    return ImageDto(
      imageUrl: image.imageUrl.fold(
        () => '',
        (imageUrl) => imageUrl.getOrCrash(),
      ),
      imageFile: image.imageFile.fold(
        () => '',
        (imageFile) => imageFile.getOrCrash().path,
      ),
    );
  }

  Image toDomain() {
    return Image(
      uploaded: imageUrl.isNotEmpty,
      imageUrl: imageUrl.isEmpty ? none() : some(ImageUrl(imageUrl)),
      imageFile: imageFile.isEmpty ? none() : some(ImageFile(File(imageFile))),
    );
  }

  factory ImageDto.fromJson(Map<String, dynamic> json) =>
      _$ImageDtoFromJson(json);
}
