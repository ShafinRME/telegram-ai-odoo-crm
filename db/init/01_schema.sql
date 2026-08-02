-- =====================================================
-- WhatsApp AI + Odoo CRM — Database Schema
-- =====================================================

-- Table: contacts
-- One row per unique WhatsApp customer
CREATE TABLE IF NOT EXISTS contacts (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    customer_name VARCHAR(255),
    email VARCHAR(255),
    company VARCHAR(255),
    language VARCHAR(10) DEFAULT 'en',
    ai_enabled BOOLEAN DEFAULT TRUE,
    human_handoff BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Table: messages
-- Every inbound and outbound message, raw log
CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    whatsapp_message_id VARCHAR(255) UNIQUE,
    phone_number VARCHAR(20) NOT NULL,
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    message_text TEXT,
    message_type VARCHAR(20) DEFAULT 'text',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Table: conversations
-- One row per phone number, tracks running state + lead data
CREATE TABLE IF NOT EXISTS conversations (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    conversation_summary TEXT,
    collected_lead_data JSONB DEFAULT '{}'::jsonb,
    lead_score INTEGER DEFAULT 0,
    odoo_lead_id INTEGER,
    last_message_at TIMESTAMPTZ DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'lead_created', 'handoff', 'closed'))
);

-- Table: processed_messages
-- Prevents duplicate processing when Meta resends webhook events
CREATE TABLE IF NOT EXISTS processed_messages (
    whatsapp_message_id VARCHAR(255) PRIMARY KEY,
    processed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for common lookups
CREATE INDEX IF NOT EXISTS idx_messages_phone ON messages(phone_number);
CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at);
CREATE INDEX IF NOT EXISTS idx_conversations_phone ON conversations(phone_number);


-- Error logging table (Day 4 addition)
CREATE TABLE IF NOT EXISTS error_logs (
    id SERIAL PRIMARY KEY,
    workflow_name VARCHAR(255),
    node_name VARCHAR(255),
    error_message TEXT,
    execution_id VARCHAR(255),
    occurred_at TIMESTAMPTZ DEFAULT NOW()
);
