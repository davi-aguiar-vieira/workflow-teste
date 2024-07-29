import requests
import json
from logging_config import setup_logger #importamos a função setup_logger
import time

logger = setup_logger() # Configura e obtém o logger

def get_resultados(contrato):
    empresasContratadas = {}

    codigo = contrato['numeroControlePNCP'].split('-')[0]
    ano = contrato['anoCompra']
    sequencial = contrato['numeroControlePNCP'].split('-')[2].split('/')[0]

        # Abaixo fiz o request para saber o número de itens de cada contratação (quantas empresas e serviços diferentes foram contratados dentro do mesmo contrato)
    try:    
        link_nItem = 'https://pncp.gov.br/api/pncp/v1/orgaos/'+codigo+'/compras/'+str(ano)+'/'+sequencial+'/itens/quantidade'
        requestItem = requests.get(link_nItem, headers={'accept': '*/*'})
        requestItem.raise_for_status()  # Levanta uma exceção para status de erro 
        nItens = requestItem.json() 

        if (nItens != 0):
            for i in range(1, (nItens+1)):
                try:
                    # Vou fazer o request para pegar os resultados de cada item (contém informações como CNPJ da empresa, qual o nome da empresa contratada e o valor recebido)
                    url = 'https://pncp.gov.br/api/pncp/v1/orgaos/'+codigo+'/compras/'+str(ano)+'/'+sequencial+'/itens/'+str(i)+'/resultados'
                    response = requests.get(url, headers={'accept': '*/*'})
                    response.raise_for_status()

                    
                    # Abaixo fiz o request para pegar outros detalhes da contratação. No caso, iremos adicionar apenas a descrição do que a empresa está fornecendo
                    url_descricao = 'https://pncp.gov.br/api/pncp/v1/orgaos/'+codigo+'/compras/'+str(ano)+'/'+sequencial+'/itens/'+str(i)+''
                    request_descricao = requests.get(url_descricao, headers={'accept': '*/*'})
                    request_descricao.raise_for_status()

                    
                    data = response.json() # JSON dos resultados do item escolhido
                    resultadoItem = data[0]
                    data_descricao = request_descricao.json() # JSON da descrição do serviço, com base no item
                    empresasContratadas['Empresa Contratada -'+str(i)] = resultadoItem['nomeRazaoSocialFornecedor']
                    empresasContratadas['CNPJ -'+str(i)] = resultadoItem["niFornecedor"]
                    empresasContratadas['Valor Recebido -'+str(i)] = resultadoItem["valorTotalHomologado"]
                    empresasContratadas['Descrição -' + str(i)] = data_descricao["descricao"]
                    
                   
                except:
                    logger.error(f"Erro ao obter contrato: {contrato['numeroControlePNCP']}")
                    print(f"Erro ao obter contrato: {contrato['numeroControlePNCP']}")
                    return None
                
            return empresasContratadas   
        
        else:
            return None
    except :
        logger.error(f"Erro ao obter contrato: {contrato['numeroControlePNCP']}")
        print(f"Erro ao obter contrato: {contrato['numeroControlePNCP']}")
        return None

pag =1
diaDt = 2
anoDt = 2021
ano_Dt=2022
mes = 1

tentativas = 5
paginas_restantes =1

dtInicial = str(anoDt) + '0'+ str(mes)+'0'+ str(diaDt) # 20220113
dtFinal = str(ano_Dt) + '0'+ str(mes)+'0'+ str(diaDt-1)

with open('frontend/contratos_OFICIAL_versao3.json', 'w', encoding='utf-8') as f:
    f.write('[\n')

    while ano_Dt <= 2025:
        
   
        while paginas_restantes>0:
            url = 'https://pncp.gov.br/api/consulta/v1/contratacoes/publicacao'
            params = {
                'dataInicial': dtInicial,
                'dataFinal': dtFinal,
                'codigoModalidadeContratacao': '8',
                'uf' : 'df',
                'pagina': str(pag)
                #'tamanhoPagina': '50'
                }
            wait_time = 1 # Tempo de espera em caso de falha na requisição

            for tentativa in range(tentativas): # Ele irá tentar 3 vezes fazer o request novamente em caso de falha
                try:
                    response = requests.get(url, params=params)
                    response.raise_for_status()
                    dados = response.json()

                    total_paginas = dados.get('totalPaginas')
                    numero_pagina = dados.get('numeroPagina')
                    paginas_restantes = dados.get('paginasRestantes')
                    total_registros = dados.get('totalRegistros')

                    print (f"Total de páginas: {total_paginas} --- Paginas restantes {paginas_restantes} --- Numero da pagina: {numero_pagina} --- Total de Registos {total_registros}")
                
                    for contrato in dados['data']:
                        if contrato['valorTotalHomologado'] is not None:
                            empresasContratadas = get_resultados(contrato)

                            if empresasContratadas:
                                

                                contrato_data = {
                                    "Modalidade" : contrato["modalidadeNome"],
                                    "Código" : contrato["numeroControlePNCP"],
                                    "UF" : contrato["unidadeOrgao"]["ufNome"],
                                    "Órgão Entidade": contrato['orgaoEntidade']['razaoSocial'],
                                    "Objeto da Compra": contrato['objetoCompra'],
                                    "Ano da Compra": contrato['anoCompra'],
                                    "Valor Total Estimado": contrato['valorTotalEstimado'],
                                    "Valor Total Homologado": contrato['valorTotalHomologado'],
                                    "Empresas Contratadas" : empresasContratadas
                                }
                                numeroControlePNCP = contrato["numeroControlePNCP"]
                                print(numeroControlePNCP)
                                json.dump(contrato_data, f, ensure_ascii=False, indent=4)
                                f.write(',\n')
                        
                    pag +=1
                    break
                except:
                    if (tentativa < tentativas - 1):
                        time.sleep(wait_time) # Espera o wait time para fazer a próxima requisição
                        wait_time *= 2 # Dobra o tempo de espera para a próxima tentativa de requisição (caso exista)
                        print(f"Tentativa número {tentativa} do requeste da pagina: {pag}, da data inicial {dtInicial} e data final {dtFinal}")
                    else:
                        logger.error(f"Nao foi possivel fazer o requeste da pagina: {pag}, da data inicial {dtInicial} e data final {dtFinal}")
                        print(f"Nao foi possivel fazer o requeste da pagina: {pag}, da data inicial {dtInicial} e data final {dtFinal}")
                        pag +=1
        
        paginas_restantes =1
        pag = 1
        anoDt = ano_Dt
        ano_Dt += 1
        dtInicial = str(anoDt) + '0'+ str(mes)+'0'+ str(diaDt)
        dtFinal = str(ano_Dt) + '0'+ str(mes)+'0'+ str(diaDt-1)
    f.seek(f.tell() - 3)  # Move o cursor de escrita de volta 3 caracteres
    f.truncate()  # Remove o último caractere (a vírgula)
    f.write('\n]')  # Escreve o fechamento da lista
    
