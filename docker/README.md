# Docker – PostgreSQL + Trino + Apache Ranger

Esta pasta contém tudo necessário para subir a integração completa:

| Serviço | Descrição | Porta |
|---|---|---|
| **postgres** | Banco de dados principal com dados mockados | 5432 |
| **trino** | Motor de consulta SQL distribuído | 8080 |
| **ranger-postgres** | Banco de metadados do Ranger (separado) | – |
| **ranger-admin** | Apache Ranger Admin (UI + REST API) | 6080 |

---

## Pré-requisitos

- Docker Engine ≥ 24
- Docker Compose v2 (`docker compose`)
- ~4 GB de RAM livres
- Conexão com internet (download do Ranger ~200 MB no primeiro build)

---

## Subindo tudo

```bash
# No diretório docker/
docker compose up --build
```

> **Nota:** O build do Ranger pode demorar 5–10 minutos na primeira vez
> (baixa o Apache Ranger 2.4.0 do mirror oficial).

### Subir apenas PostgreSQL + Trino (rápido, ~30 s)

```bash
docker compose up -d postgres trino
```

---

## Verificar saúde dos serviços

```bash
docker compose ps
# Aguardar até todos mostrarem "healthy"

# Trino
curl -s http://localhost:8080/v1/info | python3 -m json.tool

# Ranger
curl -su admin:rangeradmin1 http://localhost:6080/service/public/v2/api/servicedef \
  | python3 -m json.tool
```

---

## Consultar dados via Trino

### Usando a UI do Trino
Acesse http://localhost:8080 e execute queries na aba **Query Editor**.

### Usando curl (REST API)
```bash
# Listar catálogos
curl -s -H "X-Trino-User: analyst" \
  --data-urlencode "query=SHOW CATALOGS" \
  http://localhost:8080/v1/statement

# Selecionar funcionários
curl -s -H "X-Trino-User: analyst" \
  --data-urlencode "query=SELECT * FROM postgresql.employees.employees" \
  http://localhost:8080/v1/statement
```

### Exemplos de queries

```sql
-- Total de funcionários por departamento
SELECT department, COUNT(*) AS total, AVG(salary) AS avg_salary
FROM postgresql.employees.employees
GROUP BY department
ORDER BY avg_salary DESC;

-- Clientes com maiores transações
SELECT c.full_name, SUM(t.amount) AS total_spent
FROM postgresql.customers.customers c
JOIN postgresql.customers.transactions t ON c.id = t.customer_id
WHERE t.status = 'completed'
GROUP BY c.full_name
ORDER BY total_spent DESC
LIMIT 5;

-- Transações por status
SELECT status, COUNT(*) AS qtd, SUM(amount) AS total
FROM postgresql.customers.transactions
GROUP BY status;
```

---

## Criar políticas de mascaramento no Ranger

Após o Ranger estar saudável (`http://localhost:6080`):

```bash
chmod +x ranger/create-policies.sh
./ranger/create-policies.sh
```

### Políticas criadas automaticamente

| Tabela | Coluna | Máscara |
|---|---|---|
| `employees.employees` | `email` | Hash SHA-256 |
| `employees.employees` | `ssn` | Últimos 4 dígitos |
| `employees.employees` | `phone` | Completo (`XXXX`) |
| `customers.customers` | `email` | Hash SHA-256 |
| `customers.customers` | `credit_card` | Últimos 4 dígitos |
| `customers.customers` | `phone` | Completo (`XXXX`) |

### Interface Ranger
Acesse http://localhost:6080 com `admin` / `rangeradmin1` para visualizar e editar as políticas.

---

## Executar testes de integração

```bash
chmod +x scripts/test-integration.sh
./scripts/test-integration.sh
```

O script valida:
1. Saúde do Trino
2. Conectividade Trino → PostgreSQL
3. Visibilidade dos schemas e tabelas
4. Contagem de linhas nas tabelas mock
5. Queries de agregação (AVG, SUM, GROUP BY)
6. Presença dos campos PII
7. JOIN entre tabelas
8. Saúde do Ranger Admin
9. Existência das políticas de mascaramento

---

## Derrubar tudo

```bash
docker compose down -v   # -v remove os volumes de dados
```

---

## Estrutura de arquivos

```
docker/
├── docker-compose.yml          # Orquestração de todos os serviços
├── postgres/
│   └── init.sql                # Schema + dados mockados (PII)
├── trino/
│   └── etc/
│       ├── config.properties   # Configuração do coordinator
│       ├── node.properties
│       ├── jvm.config
│       ├── log.properties
│       └── catalog/
│           └── postgresql.properties  # Conector PostgreSQL
├── ranger/
│   ├── Dockerfile              # Imagem do Ranger Admin
│   ├── install.properties      # Configuração de instalação
│   ├── entrypoint.sh           # Script de inicialização
│   └── create-policies.sh      # Cria políticas de mascaramento via REST
└── scripts/
    ├── wait-for-service.sh     # Helper de health-check
    └── test-integration.sh     # Testes end-to-end
```

---

## Dados mockados incluídos

### `employees.employees` (10 registros)
Funcionários com `email`, `phone`, `ssn` (CPF simulado) e `salary`.

### `customers.customers` (10 registros)
Clientes com `email`, `phone` e `credit_card`.

### `customers.transactions` (14 registros)
Transações com `amount`, `status` (`completed`/`pending`/`failed`) e `description`.
