-- =============================================================
-- Mock data for PostgreSQL + Trino + Ranger integration demo
-- Tables contain PII (email, SSN, credit card) intentionally
-- so that Apache Ranger masking policies can be demonstrated.
-- =============================================================

-- Schemas
CREATE SCHEMA IF NOT EXISTS employees;
CREATE SCHEMA IF NOT EXISTS customers;

-- ---------------------------------------------------------------
-- employees.employees
-- ---------------------------------------------------------------
CREATE TABLE employees.employees (
    id          SERIAL PRIMARY KEY,
    first_name  VARCHAR(50)    NOT NULL,
    last_name   VARCHAR(50)    NOT NULL,
    email       VARCHAR(100)   NOT NULL,
    phone       VARCHAR(20),
    ssn         VARCHAR(11),          -- Social Security Number (PII)
    salary      NUMERIC(10, 2),
    department  VARCHAR(50),
    hire_date   DATE,
    is_active   BOOLEAN DEFAULT TRUE
);

INSERT INTO employees.employees
    (first_name, last_name, email, phone, ssn, salary, department, hire_date)
VALUES
    ('João',      'Silva',      'joao.silva@empresa.com',      '(11) 98765-4321', '123-45-6789', 8500.00,  'Engenharia', '2020-03-15'),
    ('Maria',     'Santos',     'maria.santos@empresa.com',     '(21) 97654-3210', '234-56-7890', 9200.00,  'Marketing',  '2019-07-22'),
    ('Carlos',    'Oliveira',   'carlos.oliveira@empresa.com',  '(31) 96543-2109', '345-67-8901', 7800.00,  'Finanças',   '2021-01-10'),
    ('Ana',       'Pereira',    'ana.pereira@empresa.com',      '(41) 95432-1098', '456-78-9012', 11000.00, 'RH',         '2018-11-05'),
    ('Pedro',     'Costa',      'pedro.costa@empresa.com',      '(51) 94321-0987', '567-89-0123', 13500.00, 'Diretoria',  '2017-06-30'),
    ('Lucia',     'Ferreira',   'lucia.ferreira@empresa.com',   '(61) 93210-9876', '678-90-1234', 8100.00,  'TI',         '2022-02-14'),
    ('Roberto',   'Almeida',    'roberto.almeida@empresa.com',  '(71) 92109-8765', '789-01-2345', 9800.00,  'Vendas',     '2020-09-08'),
    ('Fernanda',  'Rodrigues',  'fernanda.rodrigues@empresa.com','(81) 91098-7654', '890-12-3456', 10500.00, 'Jurídico',   '2019-04-17'),
    ('Marcelo',   'Lima',       'marcelo.lima@empresa.com',     '(91) 90987-6543', '901-23-4567', 7500.00,  'Operações',  '2021-08-25'),
    ('Patricia',  'Souza',      'patricia.souza@empresa.com',   '(11) 89876-5432', '012-34-5678', 12000.00, 'Engenharia', '2018-03-12');

-- ---------------------------------------------------------------
-- customers.customers
-- ---------------------------------------------------------------
CREATE TABLE customers.customers (
    id           SERIAL PRIMARY KEY,
    full_name    VARCHAR(100)  NOT NULL,
    email        VARCHAR(100)  NOT NULL,
    phone        VARCHAR(20),
    credit_card  VARCHAR(19),          -- Credit card number (PII)
    address      TEXT,
    city         VARCHAR(50),
    country      VARCHAR(50),
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO customers.customers
    (full_name, email, phone, credit_card, address, city, country)
VALUES
    ('Alice Mendes',    'alice.mendes@email.com',    '(11) 88776-5544', '4532-1234-5678-9012', 'Rua das Flores, 123',          'São Paulo',     'Brasil'),
    ('Bruno Torres',    'bruno.torres@email.com',    '(21) 87665-4433', '5425-2334-3678-9102', 'Av. Paulista, 456',            'Rio de Janeiro','Brasil'),
    ('Clara Rocha',     'clara.rocha@email.com',     '(31) 86554-3322', '3714-496353-98431',   'Rua Bahia, 789',               'Belo Horizonte','Brasil'),
    ('Diego Nunes',     'diego.nunes@email.com',     '(41) 85443-2211', '4916-2345-6789-0123', 'Rua XV de Novembro, 321',      'Curitiba',      'Brasil'),
    ('Elena Pinto',     'elena.pinto@email.com',     '(51) 84332-1100', '4532-9876-5432-1098', 'Rua da Praia, 654',            'Porto Alegre',  'Brasil'),
    ('Felipe Gomes',    'felipe.gomes@email.com',    '(61) 83221-0099', '5425-8765-4321-0987', 'SQN 210, Bloco A, 202',        'Brasília',      'Brasil'),
    ('Gabriela Castro', 'gabriela.castro@email.com', '(71) 82110-9988', '4916-7654-3210-9876', 'Rua Chile, 987',               'Salvador',      'Brasil'),
    ('Henrique Dias',   'henrique.dias@email.com',   '(81) 81009-8877', '3714-623456-78910',   'Av. Boa Viagem, 147',          'Recife',        'Brasil'),
    ('Isabela Marques', 'isabela.marques@email.com', '(85) 79998-7766', '4532-5678-9012-3456', 'Av. Beira Mar, 258',           'Fortaleza',     'Brasil'),
    ('Jonas Ribeiro',   'jonas.ribeiro@email.com',   '(91) 78887-6655', '5425-4567-8901-2345', 'Trav. Doca, 369',              'Belém',         'Brasil');

-- ---------------------------------------------------------------
-- customers.transactions
-- ---------------------------------------------------------------
CREATE TABLE customers.transactions (
    id               SERIAL PRIMARY KEY,
    customer_id      INTEGER REFERENCES customers.customers(id),
    amount           NUMERIC(12, 2),
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status           VARCHAR(20),
    description      TEXT
);

INSERT INTO customers.transactions
    (customer_id, amount, status, description)
VALUES
    (1,  150.00,  'completed', 'Compra online - Eletrônicos'),
    (1,   89.90,  'completed', 'Streaming - Assinatura mensal'),
    (2, 2500.00,  'completed', 'Passagem aérea'),
    (3,  450.00,  'pending',   'Pedido de roupas'),
    (4, 1200.00,  'completed', 'Eletrodoméstico'),
    (5,   75.50,  'completed', 'Restaurante'),
    (6, 3200.00,  'completed', 'Notebook'),
    (7,  890.00,  'failed',    'Televisão - Tentativa'),
    (8,  234.00,  'completed', 'Livros e cursos'),
    (9,  567.80,  'completed', 'Material de escritório'),
    (10,1890.00,  'completed', 'Smartphone'),
    (2,  145.00,  'completed', 'Supermercado'),
    (3,  780.00,  'completed', 'Móveis'),
    (5,   92.30,  'pending',   'Farmácia');
