"""Create synthetic Ameria-style fixture; no customer data is used."""
from xml.sax.saxutils import escape
from zipfile import ZipFile, ZIP_DEFLATED
from pathlib import Path

rows = {
  2: {'E': ('s', '0')}, 5: {'O': ('inlineStr', 'Currency'), 'Q': ('inlineStr', 'AMD')},
  19: {'D': ('inlineStr', 'Amount in card currency'), 'O': ('inlineStr', 'Transaction details')},
  20: {k: ('inlineStr', v) for k,v in {'A':'Date','B':'Amount','C':'Currency','D':'Credit','F':'Debit'}.items()},
  21: {k: ('inlineStr', v) for k,v in {'A':'01.10.2026','B':'1 000,00','C':'AMD','D':'+ 1 000,00','J':'02.10.2026','O':'Synthetic income'}.items()},
  22: {k: ('inlineStr', v) for k,v in {'A':'03.10.2026','B':'12,34','C':'USD','F':'- 4 800,00','J':'04.10.2026','O':'Synthetic merchant'}.items()},
  23: {'L': ('inlineStr', '10 000,00'), 'O': ('inlineStr', 'Synthetic balance')},
  24: {k: ('inlineStr', v) for k,v in {'A':'05.10.2026','B':'100,00','C':'AMD','F':'- 100,00','J':'05.10.2026','O':'Synthetic purchase'}.items()},
  25: {k: ('inlineStr', v) for k,v in {'A':'06.10.2026','B':'100,00','C':'AMD','J':'06.10.2026','O':'Ապասառեցում (synthetic hold release)'}.items()},
  29: {'A': ('inlineStr', 'TOTAL')}, 30: {'A': ('inlineStr', 'Fee summary'), 'G': ('inlineStr', '100,00')},
}
def sheet_rows(data):
 xmlrows=[]
 for number, cells in sorted(data.items()):
  parts=[]
  for col,(kind,value) in cells.items():
   body=f'<v>{escape(value)}</v>' if kind=='s' else f'<is><t>{escape(value)}</t></is>'
   parts.append(f'<c r="{col}{number}" t="{kind}">{body}</c>')
  xmlrows.append(f'<row r="{number}">'+''.join(parts)+'</row>')
 return ''.join(xmlrows)
ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
files={
 '[Content_Types].xml':'<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>',
 '_rels/.rels':'<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
 'xl/workbook.xml':f'<?xml version="1.0"?><workbook xmlns="{ns}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Statement" sheetId="1" r:id="rId1"/></sheets></workbook>',
 'xl/_rels/workbook.xml.rels':'<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>',
 'xl/sharedStrings.xml':f'<?xml version="1.0"?><sst xmlns="{ns}"><si><t>Ameriabank CJSC</t></si></sst>',
 'xl/worksheets/sheet1.xml':f'<?xml version="1.0"?><worksheet xmlns="{ns}"><sheetData>'+sheet_rows(rows)+'</sheetData></worksheet>',
}
with ZipFile(Path(__file__).with_name('ameria_synthetic.xlsx'),'w',ZIP_DEFLATED) as out:
 for name,content in files.items(): out.writestr(name,content)

# Separate invalid sample checks that unknown unposted rows and missing dates never disappear silently.
rows[26] = {k: ('inlineStr', v) for k,v in {'A':'07.10.2026','B':'1,00','C':'AMD','O':'Unknown non-posting'}.items()}
rows[27] = {k: ('inlineStr', v) for k,v in {'B':'2,00','C':'AMD','F':'- 2,00','O':'Missing date'}.items()}
files['xl/worksheets/sheet1.xml'] = f'<?xml version="1.0"?><worksheet xmlns="{ns}"><sheetData>'+sheet_rows(rows)+'</sheetData></worksheet>'
with ZipFile(Path(__file__).with_name('ameria_errors_synthetic.xlsx'),'w',ZIP_DEFLATED) as out:
 for name,content in files.items(): out.writestr(name,content)
