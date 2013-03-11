# -*- encoding : utf-8 -*-
require 'rubygems'
require 'prawn'
require 'prawn/measurement_extensions'
require 'barby'
require 'barby/barcode/code_128'
require 'barby/outputter/prawn_outputter'
require 'nokogiri'
require 'burocracias'

def numerify(number, decimals = 2)
  return '' if !number || number == ''
  int, frac = ("%.#{decimals}f" % number).split('.')
  int.gsub!(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1\.")  
  int + "," + frac
end

def invert(y)
  28.7.cm - y
end

module RubyDanfe

  version = "0.10.0"

  class XML
    attr_reader :xml
    def initialize(xml)
      @xml = Nokogiri::XML(xml)
    end
    def [](xpath)
      node = @xml.css(xpath)
      return node ? node.text : ''
    end
    def render
      RubyDanfe.render @xml.to_s
    end
    def collect(xpath, &block)
      result = []
      @xml.css(xpath).each do |det|
        result << yield(det)
      end
      result
    end
    def numero_nfe_formatado
      ("%09d" % self['ide/nNF']).scan(/.{3}|.+/).join(".")
    end
    def homologacao?
      self['//NFe//tpAmb'] == '2'
    end
    def previa?
      !@xml.css('protNFe nProt').any?
    end
    def chave_nfe
      self['chNFe'].present? ? self['chNFe'] : @xml.css('infNFe').first.attr('Id').gsub(/\D/, '')
    end
    def cpf_cnpj
      # self['dest/CNPJ'].present? ? self['dest/CNPJ'].insert(12, '-').insert(8, '/').insert(5, '.').insert(2, '.') : self['dest/CPF'].insert(9, '-').insert(6, '.').insert(3, '.')
      self['dest/CNPJ'] != '' ? self['dest/CNPJ'].as_cnpj : self['dest/CPF'].as_cpf
    end
  end
  
  class Document < Prawn::Document

    attr_accessor :voffset, :voffset_pos, :hprodutos, :software, :voffset_fp

    def ititle(h, w, x, y, title)
      self.text_box title, :size => 10, :at => [x.cm, invert(y.cm) - 2], :width => w.cm, :height => h.cm, :style => :bold
    end
   
    def ibarcode(h, w, x, y, info)
      Barby::Code128C.new(info).annotate_pdf(self, :x => x.cm, :y => invert(y.cm), :width => w.cm, :height => h.cm) if info != ''
    end
     
    def irectangle(h, w, x, y)
      self.stroke_rectangle [x.cm, invert(y.cm)], w.cm, h.cm
    end
    
    def ibox(h, w, x, y, title = '', info = '', options = {})
      box [x.cm, invert(y.cm)], w.cm, h.cm, title, info, options
    end

    def itext(x, y, text = '', options = {})
      draw_text text, {:at => [x.cm, invert(y.cm)]}.merge(options)
    end

    def iimage(h, w, x, y, document)
      self.image document, :at => [x.cm, invert(y.cm)], :width => (w.present? ? w.cm : nil), :height => (h.present? ? h.cm : nil)
    end
    
    def idate(h, w, x, y, title = '', info = '', options = {})
      tt = info.split('-')
      ibox(h, w, x, y, title, tt.any? ? "#{tt[2]}/#{tt[1]}/#{tt[0]}" : '', options)
    end
    
    def box(at, w, h, title = '', info = '', options = {})
      options = {
        :align => :left,
        :size => 10,
        :min_font_size => 8,
        :overflow => :shrink_to_fit,
        :style => nil,
        :valign => :top,
        :border => 1
      }.merge(options)
      self.stroke_rectangle at, w, h if options[:border] == 1
      self.text_box title, :size => 6, :at => [at[0] + 2, at[1] - 2], :width => w - 4, :height => 8 if title != ''
      self.formatted_text_box Parser.to_array(info), :size => options[:size], :at => [at[0] + 2, at[1] - (title != '' ? 14 : 4) ], :width => w - 4, :height => h - (title != '' ? 14 : 4), :align => options[:align], :style => options[:style], :valign => options[:valign], :inline_format => options[:inline_format]
    end
    
    def inumeric(h, w, x, y, title = '', info = '', options = {})
      numeric [x.cm, invert(y.cm)], w.cm, h.cm, title, info, options
    end

    def numeric(at, w, h, title = '', info = '', options = {})
      options = {:decimals => 2}.merge(options)
      info = numerify(info, options[:decimals]) if info != ''
      box at, w, h, title, info, options.merge({:align => :right})
    end
       
    def itable(h, w, x, y, data, options = {}, &block)
      self.bounding_box [x.cm, invert(y.cm)], :width => w.cm, :height => h.cm do
        self.transparent(0.0) do
          self.image File.dirname(__FILE__) + '/../data/pixel.png', :height => (self.voffset_fp).cm, :padding => 0
        end
        self.table data, options do |table|
          yield(table)
        end
      end
    end
  end
  
  def self.generatePDF(xml, options={})
  
    pdf = Document.new(
      :page_size => 'A4',
      :page_layout => :portrait,
      :left_margin => 0,
      :right_margin => 0,
      :top_margin => 0,
      :botton_margin => 0
    )
    pdf.voffset = -1.27
    pdf.voffset_pos = 0
    pdf.hprodutos = 6.77
    pdf.voffset_fp = 8
 
    pdf.font "Times-Roman" # Official font

    # Aumenta o espaço de produtos se não houver informações de ISS
    if xml['total/ISSTot'] == ''
      pdf.hprodutos += 3.82
      # pdf.hprodutos += 2.55
      pdf.voffset_pos += 2.55
      # pdf.voffset_fp += 2.55
    end
    faturas = xml.xml.css('cobr dup') rescue []
    if faturas.any?
      pdf.voffset = 0
      pdf.hprodutos -= 1.27
      pdf.voffset_pos -= 1.27
    end

    # PRODUTOS
    pdf.font_size(6) do
      pdf.itable pdf.hprodutos - 0.40 + 8, 21.50, 0.25, 10.17 + pdf.voffset,
        xml.collect('det') { |det|
          [
            det.css('prod/cProd').text, #I02
            det.css('prod/xProd').text + (det.css('infAdProd').any? ? "\n" + det.css('infAdProd').text.gsub(';', "\n") : ''), #I04
            det.css('prod/NCM').text, #I05
            det.css('ICMS/*/orig').text + det.css('ICMS/*/CST').text + det.css('ICMS/*/CSOSN').text, #N11
            det.css('prod/CFOP').text, #I08
            det.css('prod/uCom').text, #I09
            numerify(det.css('prod/qCom').text), #I10 
            numerify(det.css('prod/vUnCom').text), #I10a
            numerify(det.css('prod/vProd').text), #I11
            numerify(det.css('ICMS/*/vBC').text), #N15
            numerify(det.css('ICMS/*/vICMS').text), #N17   
            numerify(det.css('IPI/*/vIPI').text), #O14
            numerify(det.css('ICMS/*/pICMS').text), #N16
            numerify(det.css('IPI/*/pIPI').text) #O13 
          ]
        },
        :column_widths => {
          0 => 2.10.cm, 
          1 => 5.86.cm,
          2 => 1.10.cm,
          3 => 0.80.cm,
          4 => 0.80.cm,
          5 => 0.70.cm,
          6 => 1.20.cm,
          7 => 1.20.cm,
          8 => 1.50.cm,
          9 => 1.50.cm,
          10 => 1.00.cm,
          11 => 1.00.cm,
          12 => 0.90.cm,
          13 => 0.90.cm
        },
        :cell_style => {:padding => 2, :border_width => 0} do |table|
          # pdf.dash(4)
          table.column(6..13).style(:align => :right)
          table.column(0..13).border_width = 1
          table.column(0..13).borders = []
          # pdf.undash
        end
    end
    
    pdf.repeat :all do
    
      # CANHOTO
          
      pdf.ibox 0.85, 16.10, 0.25, 0.42, "RECEBEMOS DE " + xml['emit/xNome'] + " OS PRODUTOS CONSTANTES DA NOTA FISCAL INDICADA ABAIXO"
      pdf.ibox 0.85, 4.10, 0.25, 1.27, "DATA DE RECEBIMENTO"
    	pdf.ibox 0.85, 12.00, 4.35, 1.27, "IDENTIFICAÇÃO E ASSINATURA DO RECEBEDOR"

    	pdf.ibox 1.70, 4.50, 16.35, 0.42, '', 
    	  "NF-e\n" +
    	  "N°. " + xml.numero_nfe_formatado + "\n" +
    	  "Série " + "%03d" % xml['ide/serie'], {:align => :center, :valign => :center}

      # EMITENTE

      valign = :center

      if File.file?("/opt/logos_danfe/#{xml['emit/CNPJ']}.jpg")
        logo = "/opt/logos_danfe/#{xml['emit/CNPJ']}.jpg"
        # iimage(h, w, x, y, document)
        # largura da caixa / 2 - 0.5w
        pdf.iimage nil, 2.48, 2.49, 2.60, logo
        valign = :bottom
      end


      pdf.ibox 3.92, 7.46, 0.25, 2.54, '',
        "<b><font size='10'>#{xml['emit/xNome']}</font></b>" + "\n" +
        xml['enderEmit/xLgr'] + ", " + xml['enderEmit/nro'] + ", " + xml['enderEmit/xCpl'] + "\n" + 
        xml['enderEmit/xBairro'] + " - " + xml['enderEmit/CEP'].as_cep + "\n" +
        xml['enderEmit/xMun'] + " - " + xml['enderEmit/UF'] +
        (xml['enderEmit/fone'].present? ? " Fone/Fax: " + xml['enderEmit/fone'].as_phone_number : '') + " " + xml['enderEmit/email'], {:align => :center, :valign => valign, :size => 8, :inline_format => true}


      pdf.ibox 3.92, 3.08, 7.71, 2.54
      
      pdf.ibox 0.60, 3.08, 7.71, 2.54, '', "DANFE", {:size => 12, :align => :center, :border => 0, :style => :bold}
      pdf.ibox 1.20, 3.08, 7.71, 3.14, '', "Documento Auxiliar da Nota Fiscal Eletrônica", {:size => 8, :align => :center, :border => 0}
      pdf.ibox 0.60, 3.08, 7.71, 4.34, '', "#{xml['ide/tpNF']} - " + (xml['ide/tpNF'] == '0' ? 'ENTRADA' : 'SAÍDA'), {:size => 8, :align => :center, :border => 0}

      pdf.ibox 1.00, 3.08, 7.71, 4.94, '', 
    	  "N°. " + xml.numero_nfe_formatado + "\n" +
    	  "SÉRIE " + "%03d" % xml['ide/serie'], {:size => 8, :align => :center, :valign => :center, :border => 0, :style => :bold}
          
      pdf.ibox 2.20, 10.02, 10.79, 2.54
      pdf.ibarcode 1.50, 8.00, 10.9010, 4.44, xml.chave_nfe
      pdf.ibox 0.85, 10.02, 10.79, 4.74, "CHAVE DE ACESSO", xml.chave_nfe.gsub(/(\d)(?=(\d\d\d\d)+(?!\d))/, "\\1 "), {:style => :bold, :align => :center}
      pdf.ibox 0.85, 10.02, 10.79, 5.60 , '', "Consulta de autenticidade no portal nacional da NF-e\nwww.nfe.fazenda.gov.br/portal ou no site da Sefaz Autorizadora", {:align => :center, :size => 8}
  	  pdf.ibox 0.85, 10.54, 0.25, 6.46, "NATUREZA DA OPERAÇÃO", xml['ide/natOp'], {:style => :bold, :align => :center}
  	  pdf.ibox 0.85, 10.02, 10.79, 6.46, "PROTOCOLO DE AUTORIZAÇÃO DE USO", xml['infProt/nProt'] + ' - ' + (xml['infProt/dhRecbto'].present? ? DateTime.parse(xml['infProt/dhRecbto']).strftime('%d/%m/%Y %H:%M:%S') : ''), {:align => :center, :style => :bold}

  	  pdf.ibox 0.85, 6.86, 0.25, 7.31, "INSCRIÇÃO ESTADUAL", xml['emit/IE'], {:style => :bold, :align => :center}
  	  pdf.ibox 0.85, 6.86, 7.11, 7.31, "INSC.ESTADUAL DO SUBST. TRIBUTÁRIO", xml['emit/IE_ST'], {:style => :bold, :align => :center}
  	  pdf.ibox 0.85, 6.84, 13.97, 7.31, "CNPJ", (xml['emit/CNPJ'].present? ? xml['emit/CNPJ'].as_cnpj : ''), {:style => :bold, :align => :center}
    end

    # Informacoes que so aparecem na primeira pagina

    pdf.go_to_page(1)
    # TITULO

    pdf.ititle 0.42, 10.00, 0.25, 8.16, "DESTINATÁRIO / REMETENTE"

	  pdf.ibox 0.85, 12.32, 0.25, 8.58, "NOME/RAZÃO SOCIAL", xml['dest/xNome'], {:style => :bold, :align => :left, :size => 9}
	  pdf.ibox 0.85, 5.33, 12.57, 8.58, "CNPJ/CPF", xml.cpf_cnpj, {:style => :bold, :align => :center}
	  pdf.idate 0.85, 2.92, 17.90, 8.58, "DATA DA EMISSÃO", xml['ide/dEmi'], {:style => :bold, :align => :center}
	  pdf.ibox 0.85, 10.16, 0.25, 9.43, "ENDEREÇO", xml['enderDest/xLgr'] + ", " + xml['enderDest/nro'] + ", " + xml['enderDest/xCpl'], {:style => :bold, :align => :left, :size => 8}
	  pdf.ibox 0.85, 4.83, 10.41, 9.43, "BAIRRO", xml['enderDest/xBairro'], {:style => :bold, :align => :center}
	  pdf.ibox 0.85, 2.67, 15.24, 9.43, "CEP", xml['enderDest/CEP'], {:style => :bold, :align => :center}
	  pdf.idate 0.85, 2.92, 17.90, 9.43, "DATA DA SAÍDA/ENTRADA", xml['ide/dSaiEnt'], {:style => :bold, :align => :center}
	  pdf.ibox 0.85, 7.11, 0.25, 10.28, "MUNICÍPIO", xml['enderDest/xMun'], {:style => :bold, :align => :left, :size => 9}
	  pdf.ibox 0.85, 4.06, 7.36, 10.28, "FONE/FAX", xml['enderDest/fone'], {:style => :bold, :align => :center}
	  pdf.ibox 0.85, 1.14, 11.42, 10.28, "UF", xml['enderDest/UF'], {:style => :bold, :align => :center}
	  pdf.ibox 0.85, 5.33, 12.56, 10.28, "INSCRIÇÃO ESTADUAL", xml['dest/IE'], {:style => :bold, :align => :center}
	  pdf.ibox 0.85, 2.92, 17.90, 10.28, "HORA DE SAÍDA", xml['ide/hSaiEnt'], {:style => :bold, :align => :center}

    # FATURAS
    faturas = xml.xml.css('cobr dup') rescue []
    if faturas.any?
      pdf.voffset = 0
      pdf.ititle 0.42, 10.00, 0.25, 11.12, "FATURA / DUPLICATAS"
      faturas.each_with_index do |fatura, index|
        # itext(x, y, text = '', info = '', options = {})
        # ibox(h, w, x, y, title = '', info = '', options = {})
        pdf.ibox 0.85, 2.40, 2.5 * index + 0.25, 11.51
        pdf.itext 2.5 * index + 0.30, 11.75, "Num.: #{fatura.css('nDup').text}", :size => 7
        pdf.itext 2.5 * index + 0.30, 12.00, "Venc.: #{Date.parse(fatura.css('dVenc').text).strftime('%d/%m/%Y')}", :size => 7
        pdf.itext 2.5 * index + 0.30, 12.25, "Valor.: #{fatura.css('vDup').text}", :size => 7
      end
    end

    pdf.ititle 0.42, 5.60, 0.25, 12.36 + pdf.voffset, "CÁLCULO DO IMPOSTO"

  	pdf.inumeric 0.85, 4.06, 0.25, 12.78 + pdf.voffset, "BASE DE CÁLCULO DO ICMS", xml['ICMSTot/vBC'], :style => :bold
  	pdf.inumeric 0.85, 4.06, 4.31, 12.78 + pdf.voffset, "VALOR DO ICMS", xml['ICMSTot/vICMS'], :style => :bold
  	pdf.inumeric 0.85, 4.06, 8.37, 12.78 + pdf.voffset, "BASE DE CÁLCULO DO ICMS ST", xml['ICMSTot/vBCST'], :style => :bold
  	pdf.inumeric 0.85, 4.06, 12.43, 12.78 + pdf.voffset, "VALOR DO ICMS ST", xml['ICMSTot/vST'], :style => :bold
  	pdf.inumeric 0.85, 4.32, 16.49, 12.78 + pdf.voffset, "VALOR TOTAL DOS PRODUTOS", xml['ICMSTot/vProd'], :style => :bold
	  pdf.inumeric 0.85, 3.46, 0.25, 13.63 + pdf.voffset, "VALOR DO FRETE", xml['ICMSTot/vFrete'], :style => :bold
	  pdf.inumeric 0.85, 3.46, 3.71, 13.63 + pdf.voffset, "VALOR DO SEGURO", xml['ICMSTot/vSeg'], :style => :bold
	  pdf.inumeric 0.85, 3.46, 7.17, 13.63 + pdf.voffset, "DESCONTO", xml['ICMSTot/vDesc'], :style => :bold
	  pdf.inumeric 0.85, 3.46, 10.63, 13.63 + pdf.voffset, "OUTRAS DESPESAS ACESSORIAS", xml['ICMSTot/vOutro'], :style => :bold
	  pdf.inumeric 0.85, 3.46, 14.09, 13.63 + pdf.voffset, "VALOR DO IPI", xml['ICMSTot/vIPI'], :style => :bold
	  pdf.inumeric 0.85, 3.27, 17.55, 13.63 + pdf.voffset, "VALOR TOTAL DA NOTA", xml['ICMSTot/vNF'], :style => :bold
	
    pdf.ititle 0.42, 10.00, 0.25, 14.48 + pdf.voffset, "TRANSPORTADOR / VOLUMES TRANSPORTADOS"

  	pdf.ibox 0.85, 9.02, 0.25, 14.90 + pdf.voffset, "RAZÃO SOCIAL", xml['transporta/xNome'], :style => :bold
	  pdf.ibox 0.85, 2.79, 9.27, 14.90 + pdf.voffset, "FRETE POR CONTA", xml['transp/modFrete'] == '0' ? ' 0 - EMITENTE' : '1 - DEST.', :style => :bold, :align => :center
	  pdf.ibox 0.85, 1.78, 12.06, 14.90 + pdf.voffset, "CODIGO ANTT", xml['veicTransp/RNTC'], :style => :bold
	  pdf.ibox 0.85, 2.29, 13.84, 14.90 + pdf.voffset, "PLACA DO VEÍCULO", xml['veicTransp/placa'], :style => :bold
	  pdf.ibox 0.85, 0.76, 16.13, 14.90 + pdf.voffset, "UF", xml['veicTransp/UF'], :style => :bold
	  pdf.ibox 0.85, 3.94, 16.89, 14.90 + pdf.voffset, "CNPJ/CPF", xml['transporta/CNPJ'] , :style => :bold, :align => :center
  	pdf.ibox 0.85, 9.02, 0.25, 15.75 + pdf.voffset, "ENDEREÇO", xml['transporta/xEnder'], :style => :bold
  	pdf.ibox 0.85, 6.86, 9.27, 15.75 + pdf.voffset, "MUNICÍPIO", xml['transporta/xMun'], :style => :bold, :align => :center
    pdf.ibox 0.85, 0.76, 16.13, 15.75 + pdf.voffset, "UF", xml['transporta/UF'], :style => :bold
  	pdf.ibox 0.85, 3.94, 16.89, 15.75 + pdf.voffset, "INSCRIÇÂO ESTADUAL", xml['transporta/IE'], :style => :bold, :align => :center
	  pdf.ibox 0.85, 2.92, 0.25, 16.60 + pdf.voffset, "QUANTIDADE", xml['vol/qVol'], :style => :bold, :align => :center
	  pdf.ibox 0.85, 3.05, 3.17, 16.60 + pdf.voffset, "ESPÉCIE", xml['vol/esp'], :style => :bold, :align => :center
	  pdf.ibox 0.85, 3.05, 6.22, 16.60 + pdf.voffset, "MARCA", xml['vol/marca'], :style => :bold
	  pdf.ibox 0.85, 4.83, 9.27, 16.60 + pdf.voffset, "NUMERAÇÃO"
	  pdf.inumeric 0.85, 3.43, 14.10, 16.60 + pdf.voffset, "PESO BRUTO", xml['vol/pesoB'], {:decimals => 3, :style => :bold}
	  pdf.inumeric 0.85, 3.30, 17.53, 16.60 + pdf.voffset, "PESO LÍQUIDO", xml['vol/pesoL'], {:decimals => 3, :style => :bold}

    # Produtos
    pdf.page_count.times do |i|
      pdf.go_to_page(i + 1)

      if i == 1
        pdf.hprodutos += 8
        pdf.voffset_pos += 8
        pdf.voffset -= 8
      end

      pdf.ititle 0.42, 10.00, 0.25, 17.45 + pdf.voffset, "DADOS DOS PRODUTOS / SERVIÇOS"

      pdf.ibox pdf.hprodutos, 2.10, 0.25, 17.87 + pdf.voffset, "CÓDIGO PRODUTOS", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 5.86, 2.35, 17.87 + pdf.voffset, "DESCRIÇÃO DO PRODUTO / SERVIÇO", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 1.10, 8.21, 17.87 + pdf.voffset, "NCM/SH", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 0.80, 9.31, 17.87 + pdf.voffset, "O/CST", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 0.80, 10.11, 17.87 + pdf.voffset, "CFOP", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 0.70, 10.91, 17.87 + pdf.voffset, "UN", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 1.20, 11.61, 17.87 + pdf.voffset, "QUANT", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 1.20, 12.81, 17.87 + pdf.voffset, "VALOR UNIT", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 1.50, 14.01, 17.87 + pdf.voffset, "VALOR TOT", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 1.50, 15.51, 17.87 + pdf.voffset, "BASE CÁLC", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 1.00, 17.01, 17.87 + pdf.voffset, "VL ICMS", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 1.00, 18.01, 17.87 + pdf.voffset, "VL IPI", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 0.90, 19.01, 17.87 + pdf.voffset, "% ICMS", '', {:align => :center}
      pdf.ibox pdf.hprodutos, 0.90, 19.91, 17.87 + pdf.voffset, "% IPI", '', {:align => :center}

      pdf.horizontal_line 0.25.cm, 20.80.cm, :at => invert((18.17 + pdf.voffset).cm)
  	  
      if xml['total/ISSTot'] != ''
        pdf.ititle 0.42, 10.00, 0.25, 24.64 + pdf.voffset, "CÁLCULO DO ISSQN"

    	  pdf.ibox 0.85, 5.08, 0.25, 25.06 + pdf.voffset, "INSCRIÇÃO MUNICIPAL", xml['emit/IM']
    	  pdf.ibox 0.85, 5.08, 5.33, 25.06 + pdf.voffset, "VALOR TOTAL DOS SERVIÇOS", xml['total/vServ']
    	  pdf.ibox 0.85, 5.08, 10.41, 25.06 + pdf.voffset, "BASE DE CÁLCULO DO ISSQN", xml['total/vBCISS']
    	  pdf.ibox 0.85, 5.28, 15.49, 25.06 + pdf.voffset, "VALOR DO ISSQN", xml['total/ISSTot']
      end

      pdf.ititle 0.42, 10.00, 0.25, 25.91 + pdf.voffset + pdf.voffset_pos, "DADOS ADICIONAIS"

      # valor anterior: 3.07
      pdf.ibox 1.30, 12.93, 0.25, 26.33 + pdf.voffset + pdf.voffset_pos, "INFORMAÇÕES COMPLEMENTARES", xml['infAdic/infCpl'], {:size => 8, :valign => :top}
      
      pdf.ibox 1.30, 7.62, 13.17, 26.33 + pdf.voffset + pdf.voffset_pos, "RESERVADO AO FISCO"

      pdf.itext 0.25, 28.7, pdf.software, :size => 7

    end

    pdf.page_count.times do |i|
      pdf.go_to_page(i + 1)
      pdf.ibox 1.00, 3.08, 7.71, 5.54, '', 
      "FOLHA #{i + 1} de #{pdf.page_count}", {:size => 8, :align => :center, :valign => :center, :border => 0, :style => :bold}

      # MARCAS D'AGUA
      if xml.homologacao?
        pdf.fill_color "5a5a5a"
        pdf.draw_text "SEM VALOR FISCAL", :at => [65,210], :size => 50
        pdf.draw_text "AMBIENTE DE HOMOLOGAÇÃO", :at => [65,180], :size => 31
      elsif xml.previa?
        pdf.fill_color "5a5a5a"
        pdf.draw_text "SEM VALOR FISCAL", :at => [65,210], :size => 50
        pdf.draw_text "FALTA PROTOCOLO DE APROVAÇÃO DA SEFAZ", :at => [65,185], :size => 21
      end
    end
    
    return pdf
      
  end
  
  def self.render(xml_string)  
    xml = XML.new(xml_string)
    pdf = generatePDF(xml)
    return pdf.render
  end
  
  def self.generate(pdf_filename, xml_filename)
    xml = XML.new(File.new(xml_filename))
    pdf = generatePDF(xml)
    pdf.render_file pdf_filename
  end

  def self.render_file(pdf_filename, xml_string)
    xml = XML.new(xml_string)
    pdf = generatePDF(xml)
    pdf.render_file pdf_filename
  end

end
