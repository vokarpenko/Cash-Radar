# -*- coding: utf-8 -*-
"""Fully synthetic Alfa account statement; never reads a user's statement."""
from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZIP_DEFLATED, ZipFile

base=Path(__file__).parent
rows={
 7:{'A':'Выписка по счету'},
 8:{'A':'Номер счета','C':'SYNTHETIC'},
 9:{'K':'Поступления','N':'1\u00a0050 RUR'},
 10:{'A':'Валюта счета','C':'RUR','K':'Расходы','N':'350,00 RUR'},
 11:{'K':'Неподтвержденные операции','N':'0 RUR'},
 18:{'A':'Операции по счету'},
 20:{'A':'Дата операции','B':'Дата проводки','D':'Код','E':'Категория','L':'Описание','M':'Сумма в\u00a0валюте\u00a0счета','O':'Статус '},
 21:{'A':'01.11.2026','B':'02.11.2026','D':'SYNTHETIC-A','E':'Прочие операции','L':'Synthetic supermarket MCC: 5411','M':'-200','O':''},
 22:{'A':'02.11.2026','B':'02.11.2026','D':'SYNTHETIC-B','E':'Прочие операции','L':'Synthetic salary','M':'1\u00a0000','O':'Выполнен'},
 23:{'A':'03.11.2026','B':'03.11.2026','D':'SYNTHETIC-C','E':'Прочие операции','L':'Synthetic cafe MCC: 5812','M':'-150,00','O':'Выполнен'},
 24:{'A':'04.11.2026','B':'04.11.2026','D':'SYNTHETIC-D','E':'Прочие операции','L':'Synthetic refund','M':'50','O':'Выполнен'},
 26:{'A':'(подпись сотрудника АО «АЛЬФА-БАНК»)'},
}
def sheet():
 body=[]
 for number,cells in sorted(rows.items()):
  tags=[]
  for col,value in cells.items():
   tags.append(f'<c r="{col}{number}" t="inlineStr"><is><t>{escape(value)}</t></is></c>')
  body.append(f'<row r="{number}">'+''.join(tags)+'</row>')
 return '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'+''.join(body)+'</sheetData></worksheet>'
with ZipFile(base/'ameria_synthetic.xlsx') as source:
 files={item.filename:source.read(item.filename) for item in source.infolist()}
files['xl/sharedStrings.xml']=b'<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>ALFA SYNTHETIC</t></si></sst>'
def save(name):
 files['xl/worksheets/sheet1.xml']=sheet().encode()
 with ZipFile(base/name,'w',ZIP_DEFLATED) as target:
  for name,data in files.items(): target.writestr(name,data)
# Bank marker is a static, non-sensitive fixture string.
files['xl/sharedStrings.xml']='<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>АО «АЛЬФА-БАНК»</t></si></sst>'.encode()
save('alfa_synthetic.xlsx')
rows[11]['N']='10 RUR'
save('alfa_pending_synthetic.xlsx')
rows[11]['N']='0 RUR'; rows[10]['N']='351 RUR'
save('alfa_unbalanced_synthetic.xlsx')
rows[10]['N']='350 RUR'; rows[21]['L']='Synthetic payment MCC: 54XX'
save('alfa_bad_mcc_synthetic.xlsx')
