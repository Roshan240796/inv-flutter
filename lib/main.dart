import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const baseUrl = 'http://10.0.2.2:8080';
const username = 'admin';
const password = 'admin';

void main() {
  runApp(const InvoiceApp());
}

class InvoiceApp extends StatelessWidget {
  const InvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Invoice Operations',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff146c94),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const InvoiceHomePage(),
    );
  }
}

class Invoice {
  const Invoice({
    required this.number,
    required this.customer,
    required this.amount,
    required this.currency,
    required this.status,
    required this.issuedOn,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      number: json['number'] as String,
      customer: json['customer'] as String,
      amount: double.parse(json['amount'].toString()),
      currency: json['currency'] as String,
      status: json['status'] as String,
      issuedOn: DateTime.parse(json['issuedOn'] as String),
    );
  }

  final String number;
  final String customer;
  final double amount;
  final String currency;
  final String status;
  final DateTime issuedOn;
}

class InvoiceHomePage extends StatefulWidget {
  const InvoiceHomePage({super.key});

  @override
  State<InvoiceHomePage> createState() => _InvoiceHomePageState();
}

class _InvoiceHomePageState extends State<InvoiceHomePage> {
  final _client = http.Client();
  late Future<List<Invoice>> _invoices;

  String get _authHeader => 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  @override
  void initState() {
    super.initState();
    _invoices = _loadInvoices();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<List<Invoice>> _loadInvoices() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/invoices'),
      headers: {'Authorization': _authHeader},
    );
    if (response.statusCode != 200) {
      throw Exception('Could not load invoices (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => Invoice.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _createInvoice(String customer, double amount, String currency) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/invoices'),
      headers: {
        'Authorization': _authHeader,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'customer': customer,
        'amount': amount,
        'currency': currency,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('Could not create invoice (${response.statusCode})');
    }
    setState(() {
      _invoices = _loadInvoices();
    });
  }

  Future<void> _showCreateInvoice() async {
    final result = await showDialog<({String customer, double amount, String currency})>(
      context: context,
      builder: (_) => const _CreateInvoiceDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await _createInvoice(result.customer, result.amount, result.currency);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice created')),
        );
      }
    } catch (error) {
      if (mounted) _showError(error.toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _refreshInvoices() {
    setState(() {
      _invoices = _loadInvoices();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Operations'),
        actions: [
          IconButton(
            tooltip: 'Refresh invoices',
            onPressed: _refreshInvoices,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateInvoice,
        icon: const Icon(Icons.add),
        label: const Text('New invoice'),
      ),
      body: FutureBuilder<List<Invoice>>(
        future: _invoices,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refreshInvoices,
            );
          }
          final invoices = snapshot.data ?? const <Invoice>[];
          final total = invoices.fold<double>(0, (sum, invoice) => sum + invoice.amount);
          return RefreshIndicator(
            onRefresh: () async {
              _refreshInvoices();
              try {
                await _invoices;
              } catch (_) {
              }
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                Text('Delivery overview', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                const Text('Track invoice exchange and client delivery status.'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _Metric(label: 'Invoices', value: '${invoices.length}', icon: Icons.receipt_long),
                    const SizedBox(width: 12),
                    _Metric(label: 'Total value', value: 'EUR ${total.toStringAsFixed(2)}', icon: Icons.euro),
                  ],
                ),
                const SizedBox(height: 28),
                Text('Recent invoices', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                ...invoices.map((invoice) => _InvoiceTile(invoice: invoice)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label),
          ]),
        ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(invoice.customer.substring(0, 1))),
        title: Text(invoice.number),
        subtitle: Text('${invoice.customer}  |  ${invoice.issuedOn.toLocal().toString().split(' ').first}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${invoice.currency} ${invoice.amount.toStringAsFixed(2)}'),
            Text(invoice.status, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          const Text('The invoice service is unavailable.'),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      ),
    );
  }
}

class _CreateInvoiceDialog extends StatefulWidget {
  const _CreateInvoiceDialog();

  @override
  State<_CreateInvoiceDialog> createState() => _CreateInvoiceDialogState();
}

class _CreateInvoiceDialogState extends State<_CreateInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _amount = TextEditingController();
  String _currency = 'EUR';

  @override
  void dispose() {
    _customer.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New invoice'),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: _customer, decoration: const InputDecoration(labelText: 'Customer'), validator: _required),
          TextFormField(controller: _amount, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _validAmount),
          DropdownButtonFormField<String>(initialValue: _currency, decoration: const InputDecoration(labelText: 'Currency'), items: const [
            DropdownMenuItem(value: 'EUR', child: Text('EUR')),
            DropdownMenuItem(value: 'USD', child: Text('USD')),
          ], onChanged: (value) => setState(() => _currency = value ?? 'EUR')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, (customer: _customer.text.trim(), amount: double.parse(_amount.text), currency: _currency));
        }, child: const Text('Create')),
      ],
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;

  String? _validAmount(String? value) {
    final amount = double.tryParse(value ?? '');
    return amount == null || amount <= 0 ? 'Enter a positive amount' : null;
  }
}
