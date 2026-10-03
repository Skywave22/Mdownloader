/// A named browse row the extension itself defines (a Legado explore link,
/// or a future backend hook). The app renders these as rails in addition to
/// the standard Popular/Latest hooks.
class DSection {
  final String id;
  final String name;

  const DSection({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory DSection.fromJson(Map<String, dynamic> json) => DSection(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}
