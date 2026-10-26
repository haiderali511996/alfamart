import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Cell styles defined in [XlsxWorkbook._stylesXml].
class XStyle {
  static const normal = 0;
  static const header = 1;
  static const money = 2;
  static const totalMoney = 3;
  static const title = 4;
  static const totalLabel = 5;
  static const text = 6;
  static const note = 7;
  static const subtitle = 8;
  static const moneyBold = 9;
  static const integer = 10;
  static const percent = 11;
}

class _Cell {
  _Cell({this.text, this.number, this.formula, this.cachedText, required this.style});
  final String? text;
  final num? number;
  final String? formula;

  /// Cached result of a formula that evaluates to text (e.g. "").
  final String? cachedText;
  final int style;
}

class XlsxSheet {
  XlsxSheet(this.name);

  final String name;
  final Map<int, Map<int, _Cell>> _rows = {};
  final Map<int, double> _widths = {};
  int? freezeRows;
  int? freezeCols;
  final List<String> _merges = [];

  /// Excel reference such as `A1` for zero-based [row] / [col].
  static String ref(int row, int col, {bool absRow = false, bool absCol = false}) =>
      '${absCol ? r'$' : ''}${colName(col)}${absRow ? r'$' : ''}${row + 1}';

  static String colName(int col) {
    var n = col + 1;
    var s = '';
    while (n > 0) {
      final m = (n - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  /// Name usable inside formulas, e.g. `'Counter 1'`.
  String get quoted => "'${name.replaceAll("'", "''")}'";

  void width(int col, double w) => _widths[col] = w;

  void text(int row, int col, String value, {int style = XStyle.text}) =>
      (_rows[row] ??= {})[col] = _Cell(text: value, style: style);

  void number(int row, int col, num value, {int style = XStyle.money}) =>
      (_rows[row] ??= {})[col] = _Cell(number: value, style: style);

  /// A live formula. [cached] is what the formula evaluates to now, so
  /// viewers that do not recalculate still show correct numbers.
  void formula(int row, int col, String f, {num? cached, String? cachedText, int style = XStyle.money}) =>
      (_rows[row] ??= {})[col] = _Cell(formula: f, number: cached, cachedText: cachedText, style: style);

  void merge(int r1, int c1, int r2, int c2) => _merges.add('${ref(r1, c1)}:${ref(r2, c2)}');

  String _xml() {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    b.write('<sheetViews><sheetView workbookViewId="0">');
    if ((freezeRows ?? 0) > 0 || (freezeCols ?? 0) > 0) {
      final fr = freezeRows ?? 0, fc = freezeCols ?? 0;
      final pane = fr > 0 && fc > 0 ? 'bottomRight' : (fr > 0 ? 'bottomLeft' : 'topRight');
      b.write('<pane ${fc > 0 ? 'xSplit="$fc" ' : ''}${fr > 0 ? 'ySplit="$fr" ' : ''}'
          'topLeftCell="${ref(fr, fc)}" activePane="$pane" state="frozen"/>');
    }
    b.write('</sheetView></sheetViews>');
    b.write('<sheetFormatPr defaultRowHeight="15"/>');
    if (_widths.isNotEmpty) {
      b.write('<cols>');
      final keys = _widths.keys.toList()..sort();
      for (final c in keys) {
        b.write('<col min="${c + 1}" max="${c + 1}" width="${_widths[c]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    final rowKeys = _rows.keys.toList()..sort();
    for (final r in rowKeys) {
      b.write('<row r="${r + 1}">');
      final cells = _rows[r]!;
      final colKeys = cells.keys.toList()..sort();
      for (final c in colKeys) {
        final cell = cells[c]!;
        final at = 'r="${ref(r, c)}" s="${cell.style}"';
        if (cell.formula != null) {
          final f = '<f>${_esc(cell.formula!)}</f>';
          if (cell.cachedText != null) {
            b.write('<c $at t="str">$f<v>${_esc(cell.cachedText!)}</v></c>');
          } else if (cell.number != null) {
            b.write('<c $at>$f<v>${_num(cell.number!)}</v></c>');
          } else {
            b.write('<c $at>$f</c>');
          }
        } else if (cell.number != null) {
          b.write('<c $at><v>${_num(cell.number!)}</v></c>');
        } else {
          b.write('<c $at t="inlineStr"><is><t xml:space="preserve">${_esc(cell.text ?? '')}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (_merges.isNotEmpty) {
      b.write('<mergeCells count="${_merges.length}">');
      for (final m in _merges) {
        b.write('<mergeCell ref="$m"/>');
      }
      b.write('</mergeCells>');
    }
    b.write('<pageMargins left="0.5" right="0.5" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>');
    b.write('<pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/>');
    b.write('</worksheet>');
    return b.toString();
  }

  static String _num(num v) {
    if (v is int) return v.toString();
    final d = v.toDouble();
    if (d == d.roundToDouble()) return d.toInt().toString();
    return d.toString();
  }
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// Minimal, dependency free .xlsx writer with real formulas. The workbook
/// is flagged to fully recalculate on open, so any value edited in Excel
/// flows through every formula on every sheet.
class XlsxWorkbook {
  final List<XlsxSheet> sheets = [];
  String creator = 'Alfa Mart Cash Flow';

  /// Excel sheet names: max 31 chars, no []:*?/\ and unique.
  XlsxSheet addSheet(String name) {
    var clean = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (clean.isEmpty) clean = 'Sheet';
    if (clean.length > 31) clean = clean.substring(0, 31);
    var unique = clean;
    var i = 2;
    while (sheets.any((s) => s.name.toLowerCase() == unique.toLowerCase())) {
      final suffix = ' ($i)';
      unique = (clean.length + suffix.length > 31 ? clean.substring(0, 31 - suffix.length) : clean) + suffix;
      i++;
    }
    final s = XlsxSheet(unique);
    sheets.add(s);
    return s;
  }

  Uint8List encode() {
    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile.bytes(path, bytes));
    }

    add('[Content_Types].xml', _contentTypes());
    add('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '</Relationships>');
    final now = DateTime.now().toUtc().toIso8601String().split('.').first;
    add('docProps/core.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:creator>${_esc(creator)}</dc:creator>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${now}Z</dcterms:created>'
        '</cp:coreProperties>');
    add('docProps/app.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
        '<Application>Alfa Mart Cash Flow</Application></Properties>');
    final wb = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
      ..write('<bookViews><workbookView activeTab="0"/></bookViews><sheets>');
    final rels = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (var i = 0; i < sheets.length; i++) {
      wb.write('<sheet name="${_esc(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
      rels.write('<Relationship Id="rId${i + 1}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
          'Target="worksheets/sheet${i + 1}.xml"/>');
      add('xl/worksheets/sheet${i + 1}.xml', sheets[i]._xml());
    }
    wb.write('</sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>');
    rels.write('<Relationship Id="rId${sheets.length + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
    rels.write('</Relationships>');
    add('xl/workbook.xml', wb.toString());
    add('xl/_rels/workbook.xml.rels', rels.toString());
    add('xl/styles.xml', _stylesXml);
    return ZipEncoder().encodeBytes(archive);
  }

  String _contentTypes() {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write('<Override PartName="/xl/workbook.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
      ..write('<Override PartName="/xl/styles.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
      ..write('<Override PartName="/docProps/core.xml" '
          'ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>')
      ..write('<Override PartName="/docProps/app.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>');
    for (var i = 0; i < sheets.length; i++) {
      b.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    }
    b.write('</Types>');
    return b.toString();
  }

  // Brand colours: navy 011E65, orange FD6900.
  static const _stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00;[Red]-#,##0.00"/></numFmts>'
      '<fonts count="6">'
      '<font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="16"/><color rgb="FF011E65"/><name val="Calibri"/></font>'
      '<font><i/><sz val="10"/><color rgb="FF666666"/><name val="Calibri"/></font>'
      '<font><b/><sz val="12"/><color rgb="FFFD6900"/><name val="Calibri"/></font>'
      '</fonts>'
      '<fills count="4">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF011E65"/><bgColor indexed="64"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFFFE8D6"/><bgColor indexed="64"/></patternFill></fill>'
      '</fills>'
      '<borders count="2">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border><left style="thin"><color rgb="FFD0D5E0"/></left><right style="thin"><color rgb="FFD0D5E0"/></right>'
      '<top style="thin"><color rgb="FFD0D5E0"/></top><bottom style="thin"><color rgb="FFD0D5E0"/></bottom><diagonal/></border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="12">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      '<xf numFmtId="164" fontId="2" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
      '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>'
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="5" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="164" fontId="2" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/>'
      '<xf numFmtId="1" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      '<xf numFmtId="10" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}
