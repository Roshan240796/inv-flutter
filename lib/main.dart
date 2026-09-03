import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const baseUrl = 'http://10.0.2.2:8080';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'jwt_token';
  static const _refreshTokenKey = 'refresh_token';

  static Future<String?> loadToken() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null || !_isExpired(token)) return token;
    return _refreshAccessToken();
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  static bool _isExpired(String token) {
    try {
      final parts = token.split('.');
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
      final expiry = (payload['exp'] as num).toInt();
      return DateTime.now().millisecondsSinceEpoch >= expiry * 1000 - 30000;
    } catch (_) {
      return true;
    }
  }

  static Future<String?> _refreshAccessToken() async {
    final refresh = await _storage.read(key: _refreshTokenKey);
    if (refresh == null || refresh.isEmpty) { await clearToken(); return null; }
    final response = await http.post(Uri.parse('$baseUrl/api/auth/refresh'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refreshToken': refresh}));
    if (response.statusCode != 200) { await clearToken(); return null; }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    final nextRefresh = body['refreshToken'] as String?;
    if (token == null || nextRefresh == null) { await clearToken(); return null; }
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _refreshTokenKey, value: nextRefresh);
    return token;
  }

  static Future<String> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode != 200) {
      throw Exception('Invalid username or password.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Authentication token missing.');
    }

    await _storage.write(key: _tokenKey, value: token);
    final refreshToken = body['refreshToken'] as String?;
    if (refreshToken != null) await _storage.write(key: _refreshTokenKey, value: refreshToken);
    return token;
  }

  static Future<List<InvoiceSummary>> fetchInvoices({
    String search = '',
    String customer = '',
    String? status,
    String? currency,
    DateTime? issuedFrom,
    DateTime? issuedTo,
    int page = 0,
    int size = 20,
    String sort = 'issuedOn,desc',
  }) async {
    final token = await loadToken();
    if (token == null || token.isEmpty) {
      throw const SessionExpiredException();
    }

    final query = <String, String>{
      'page': '$page', 'size': '$size', 'sort': sort,
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (customer.trim().isNotEmpty) 'customer': customer.trim(),
      if (status != null) 'status': status,
      if (currency != null) 'currency': currency,
      if (issuedFrom != null) 'issuedFrom': issuedFrom.toIso8601String().split('T').first,
      if (issuedTo != null) 'issuedTo': issuedTo.toIso8601String().split('T').first,
    };
    final response = await http.get(
      Uri.parse('$baseUrl/api/invoices').replace(queryParameters: query),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      await clearToken();
      throw const SessionExpiredException();
    }

    if (response.statusCode != 200) {
      throw Exception('Could not load invoices (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    final data = decoded is List ? decoded : (decoded as Map<String, dynamic>)['content'] as List<dynamic>;
    return data
        .map((item) => InvoiceSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<void> deleteInvoice(int invoiceId) async {
    final response = await _authorized('DELETE', '/api/invoices/$invoiceId');
    if (response.statusCode == 401 || response.statusCode == 403) throw const SessionExpiredException();
    if (response.statusCode != 204) throw Exception('Could not delete invoice (${response.statusCode})');
  }

  static Future<InvoiceSummary> updateStatus(int invoiceId, String status, {String? rejectionReason}) async {
    final response = await _authorized('PATCH', '/api/invoices/$invoiceId/status', body: {
      'status': status,
      if (rejectionReason != null && rejectionReason.trim().isNotEmpty) 'rejectionReason': rejectionReason.trim(),
    });
    if (response.statusCode == 401 || response.statusCode == 403) throw const SessionExpiredException();
    if (response.statusCode != 200) throw Exception('Could not update status (${response.statusCode})');
    return InvoiceSummary.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<http.Response> _authorized(String method, String path, {Map<String, dynamic>? body}) async {
    final token = await loadToken();
    if (token == null || token.isEmpty) throw const SessionExpiredException();
    final headers = {'Authorization': 'Bearer $token', 'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    final request = http.Request(method, Uri.parse('$baseUrl$path'))..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    return http.Response.fromStream(await request.send());
  }

  static Future<InvoiceDetail> fetchInvoiceDetail(int invoiceId) async {
    final token = await loadToken();
    if (token == null || token.isEmpty) {
      throw const SessionExpiredException();
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/invoices/$invoiceId'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      await clearToken();
      throw const SessionExpiredException();
    }

    if (response.statusCode != 200) {
      throw Exception('Could not load invoice detail (${response.statusCode})');
    }

    return InvoiceDetail.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<InvoiceDetail> updateInvoiceInfo(int invoiceId, Map<String, dynamic> data) async {
    final token = await loadToken();
    if (token == null || token.isEmpty) {
      throw const SessionExpiredException();
    }

    final response = await http.put(
      Uri.parse('$baseUrl/api/invoices/$invoiceId/info'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      await clearToken();
      throw const SessionExpiredException();
    }

    if (response.statusCode != 200) {
      throw Exception('Could not update invoice (${response.statusCode})');
    }

    return InvoiceDetail.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<InvoiceLineItem> addLineItem(int invoiceId, Map<String, dynamic> data) async {
    final token = await loadToken();
    if (token == null || token.isEmpty) {
      throw const SessionExpiredException();
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/invoices/$invoiceId/line-items'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      await clearToken();
      throw const SessionExpiredException();
    }

    if (response.statusCode != 201) {
      throw Exception('Could not add line item (${response.statusCode})');
    }

    return InvoiceLineItem.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<void> deleteLineItem(int invoiceId, int lineItemId) async {
    final token = await loadToken();
    if (token == null || token.isEmpty) {
      throw const SessionExpiredException();
    }

    final response = await http.delete(
      Uri.parse('$baseUrl/api/invoices/$invoiceId/line-items/$lineItemId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      await clearToken();
      throw const SessionExpiredException();
    }

    if (response.statusCode != 204) {
      throw Exception('Could not delete line item (${response.statusCode})');
    }
  }
}

class SessionExpiredException implements Exception {
  const SessionExpiredException();
}

class InvoiceSummary {
  const InvoiceSummary({
    required this.id,
    required this.number,
    required this.customer,
    required this.amount,
    required this.currency,
    required this.status,
    required this.issuedOn,
  });

  final int id;
  final String number;
  final String customer;
  final double amount;
  final String currency;
  final String status;
  final DateTime issuedOn;

  factory InvoiceSummary.fromJson(Map<String, dynamic> json) {
    return InvoiceSummary(
      id: json['id'] as int,
      number: json['number'] as String,
      customer: json['customer'] as String,
      amount: double.parse(json['amount'].toString()),
      currency: json['currency'] as String,
      status: json['status'] as String,
      issuedOn: DateTime.parse(json['issuedOn'] as String),
    );
  }
}

class InvoiceDetail {
  const InvoiceDetail({
    required this.id,
    required this.number,
    required this.customer,
    required this.customerAddress,
    required this.customerContactEmail,
    required this.customerContactPhone,
    required this.supplier,
    required this.supplierAddress,
    required this.supplierContactEmail,
    required this.supplierContactPhone,
    required this.issuedOn,
    required this.dueDate,
    required this.subtotal,
    required this.discountAmount,
    required this.discountPercentage,
    required this.taxAmount,
    required this.taxPercentage,
    required this.amount,
    required this.currency,
    required this.paymentTerms,
    required this.status,
    required this.notes,
    required this.lineItems,
    required this.attachments,
  });

  final int id;
  final String number;
  final String customer;
  final String? customerAddress;
  final String? customerContactEmail;
  final String? customerContactPhone;
  final String? supplier;
  final String? supplierAddress;
  final String? supplierContactEmail;
  final String? supplierContactPhone;
  final DateTime issuedOn;
  final DateTime? dueDate;
  final double subtotal;
  final double discountAmount;
  final double discountPercentage;
  final double taxAmount;
  final double taxPercentage;
  final double amount;
  final String currency;
  final String? paymentTerms;
  final String status;
  final String? notes;
  final List<InvoiceLineItem> lineItems;
  final List<InvoiceAttachment> attachments;

  factory InvoiceDetail.fromJson(Map<String, dynamic> json) {
    return InvoiceDetail(
      id: json['id'] as int,
      number: json['number'] as String,
      customer: json['customer'] as String,
      customerAddress: json['customerAddress'] as String?,
      customerContactEmail: json['customerContactEmail'] as String?,
      customerContactPhone: json['customerContactPhone'] as String?,
      supplier: json['supplier'] as String?,
      supplierAddress: json['supplierAddress'] as String?,
      supplierContactEmail: json['supplierContactEmail'] as String?,
      supplierContactPhone: json['supplierContactPhone'] as String?,
      issuedOn: DateTime.parse(json['issuedOn'] as String),
      dueDate: json['dueDate'] == null ? null : DateTime.parse(json['dueDate'] as String),
      subtotal: double.parse(json['subtotal'].toString()),
      discountAmount: double.parse(json['discountAmount'].toString()),
      discountPercentage: double.parse(json['discountPercentage'].toString()),
      taxAmount: double.parse(json['taxAmount'].toString()),
      taxPercentage: double.parse(json['taxPercentage'].toString()),
      amount: double.parse(json['amount'].toString()),
      currency: json['currency'] as String,
      paymentTerms: json['paymentTerms'] as String?,
      status: json['status'] as String,
      notes: json['notes'] as String?,
      lineItems: (json['lineItems'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => InvoiceLineItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      attachments: (json['attachments'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => InvoiceAttachment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class InvoiceLineItem {
  const InvoiceLineItem({
    required this.id,
    required this.lineNumber,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.taxPercentage,
    required this.discountPercentage,
    required this.lineSubtotal,
    required this.lineDiscount,
    required this.lineTax,
    required this.lineTotal,
  });

  final int id;
  final int lineNumber;
  final String description;
  final double quantity;
  final double unitPrice;
  final double taxPercentage;
  final double discountPercentage;
  final double lineSubtotal;
  final double lineDiscount;
  final double lineTax;
  final double lineTotal;

  factory InvoiceLineItem.fromJson(Map<String, dynamic> json) {
    return InvoiceLineItem(
      id: json['id'] as int,
      lineNumber: json['lineNumber'] as int,
      description: json['description'] as String,
      quantity: double.parse(json['quantity'].toString()),
      unitPrice: double.parse(json['unitPrice'].toString()),
      taxPercentage: double.parse(json['taxPercentage'].toString()),
      discountPercentage: double.parse(json['discountPercentage'].toString()),
      lineSubtotal: double.parse(json['lineSubtotal'].toString()),
      lineDiscount: double.parse(json['lineDiscount'].toString()),
      lineTax: double.parse(json['lineTax'].toString()),
      lineTotal: double.parse(json['lineTotal'].toString()),
    );
  }
}

class InvoiceAttachment {
  const InvoiceAttachment({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.description,
    required this.uploadedAt,
  });

  final int id;
  final String fileName;
  final String fileType;
  final int fileSize;
  final String? description;
  final DateTime uploadedAt;

  factory InvoiceAttachment.fromJson(Map<String, dynamic> json) {
    return InvoiceAttachment(
      id: json['id'] as int,
      fileName: json['fileName'] as String,
      fileType: json['fileType'] as String,
      fileSize: (json['fileSize'] as num).toInt(),
      description: json['description'] as String?,
      uploadedAt: DateTime.parse(json['uploadedAt'] as String),
    );
  }
}

void main() {
  runApp(const InvoiceApp());
}

class InvoiceApp extends StatefulWidget {
  const InvoiceApp({super.key});

  @override
  State<InvoiceApp> createState() => _InvoiceAppState();
}

class _InvoiceAppState extends State<InvoiceApp> {
  String? _token;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final token = await AuthService.loadToken();
    if (!mounted) return;
    setState(() {
      _token = token;
      _loading = false;
    });
  }

  void _loggedIn(String token) => setState(() {
        _token = token;
      });

  Future<void> _logout() async {
    await AuthService.clearToken();
    if (mounted) {
      setState(() => _token = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      title: 'Invoice Operations',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff146c94),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: _token == null
          ? _LoginPage(onLoggedIn: _loggedIn)
          : InvoiceHomePage(token: _token!, onLogout: _logout),
    );
  }
}

class InvoiceHomePage extends StatefulWidget {
  const InvoiceHomePage({super.key, required this.token, required this.onLogout});

  final String token;
  final Future<void> Function() onLogout;

  @override
  State<InvoiceHomePage> createState() => _InvoiceHomePageState();
}

class _InvoiceHomePageState extends State<InvoiceHomePage> {
  late Future<List<InvoiceSummary>> _invoices;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String? _statusFilter;
  String? _currencyFilter;
  String _sort = 'issuedOn,desc';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _invoices = AuthService.fetchInvoices();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _queryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _page = 0;
      _refreshInvoices();
    });
  }

  Future<void> _refreshInvoices() async {
    setState(() {
      _invoices = AuthService.fetchInvoices(
        search: _searchController.text,
        status: _statusFilter,
        currency: _currencyFilter,
        page: _page,
        sort: _sort,
      );
    });
  }

  Future<void> _deleteInvoice(InvoiceSummary invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete invoice?'),
        content: Text('Delete ${invoice.number}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthService.deleteInvoice(invoice.id);
      await _refreshInvoices();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete invoice: $error')));
    }
  }

  Future<void> _logoutAndReturn() async {
    await widget.onLogout();
  }

  void _openInvoiceDetail(int invoiceId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InvoiceDetailPage(
          invoiceId: invoiceId,
          token: widget.token,
          onLogout: _logoutAndReturn,
          onRefresh: _refreshInvoices,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await widget.onLogout();
            },
          ),
        ],
      ),
      body: FutureBuilder<List<InvoiceSummary>>(
        future: _invoices,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            if (error is SessionExpiredException) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await widget.onLogout();
              });
            }
            return _ErrorState(
              message: error.toString(),
              onRetry: _refreshInvoices,
            );
          }

          final invoices = snapshot.data ?? const <InvoiceSummary>[];
          final total = invoices.fold<double>(0, (sum, item) => sum + item.amount);

          return RefreshIndicator(
            onRefresh: () async => _refreshInvoices(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                Text(
                  'Delivery overview',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('Track invoice exchange and client delivery status.'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _Metric(
                      label: 'Invoices',
                      value: '${invoices.length}',
                      icon: Icons.receipt_long,
                    ),
                    const SizedBox(width: 12),
                    _Metric(
                      label: 'Total value',
                      value: '${invoices.firstOrNull?.currency ?? 'EUR'} ${total.toStringAsFixed(2)}',
                      icon: Icons.euro,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _searchController,
                  onChanged: _queryChanged,
                  decoration: const InputDecoration(
                    labelText: 'Search invoices',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: _statusFilter,
                        decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem<String?>(value: null, child: Text('All statuses')),
                          DropdownMenuItem(value: 'DRAFT', child: Text('Draft')),
                          DropdownMenuItem(value: 'SUBMITTED', child: Text('Submitted')),
                          DropdownMenuItem(value: 'APPROVED', child: Text('Approved')),
                          DropdownMenuItem(value: 'REJECTED', child: Text('Rejected')),
                          DropdownMenuItem(value: 'PAID', child: Text('Paid')),
                        ],
                        onChanged: (value) { setState(() { _statusFilter = value; _page = 0; }); _refreshInvoices(); },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _sort,
                        decoration: const InputDecoration(labelText: 'Sort', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'issuedOn,desc', child: Text('Newest')),
                          DropdownMenuItem(value: 'issuedOn,asc', child: Text('Oldest')),
                          DropdownMenuItem(value: 'amount,desc', child: Text('Highest amount')),
                          DropdownMenuItem(value: 'amount,asc', child: Text('Lowest amount')),
                          DropdownMenuItem(value: 'number,asc', child: Text('Invoice number')),
                        ],
                        onChanged: (value) { if (value == null) return; setState(() { _sort = value; _page = 0; }); _refreshInvoices(); },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Recent invoices', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                for (final invoice in invoices)
                  _InvoiceTile(
                    invoice: invoice,
                    onTap: () => _openInvoiceDetail(invoice.id),
                    onDelete: () => _deleteInvoice(invoice),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(onPressed: _page == 0 ? null : () { setState(() => _page--); _refreshInvoices(); }, icon: const Icon(Icons.chevron_left)),
                    Text('Page ${_page + 1}'),
                    IconButton(onPressed: invoices.length < 20 ? null : () { setState(() => _page++); _refreshInvoices(); }, icon: const Icon(Icons.chevron_right)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateInvoice,
        icon: const Icon(Icons.add),
        label: const Text('New invoice'),
      ),
    );
  }

  Future<void> _showCreateInvoice() async {
    final result = await showDialog<({String customer, double amount, String currency})>(
      context: context,
      builder: (_) => const _CreateInvoiceDialog(),
    );

    if (result == null || !mounted) return;

    try {
      final payload = {
        'customer': result.customer,
        'amount': result.amount,
        'currency': result.currency,
      };

      await http.post(
        Uri.parse('$baseUrl/api/invoices'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (mounted) {
        await _refreshInvoices();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice created successfully')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating invoice: $error')),
        );
      }
    }
  }
}

class InvoiceDetailPage extends StatefulWidget {
  const InvoiceDetailPage({
    super.key,
    required this.invoiceId,
    required this.token,
    required this.onLogout,
    required this.onRefresh,
  });

  final int invoiceId;
  final String token;
  final Future<void> Function() onLogout;
  final Future<void> Function() onRefresh;

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  late Future<InvoiceDetail> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = AuthService.fetchInvoiceDetail(widget.invoiceId);
  }

  Future<void> _refresh() async {
    setState(() {
      _detailFuture = AuthService.fetchInvoiceDetail(widget.invoiceId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
            widget.onRefresh();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await widget.onLogout();
            },
          ),
        ],
      ),
      body: FutureBuilder<InvoiceDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final invoice = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InvoiceHeader(invoice: invoice),
                  _StatusActions(
                    invoice: invoice,
                    onChanged: _refresh,
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    title: 'Customer',
                    children: [
                      Text(invoice.customer),
                      if (invoice.customerAddress != null && invoice.customerAddress!.isNotEmpty)
                        Text('Address: ${invoice.customerAddress}'),
                      if (invoice.customerContactEmail != null && invoice.customerContactEmail!.isNotEmpty)
                        Text('Email: ${invoice.customerContactEmail}'),
                      if (invoice.customerContactPhone != null && invoice.customerContactPhone!.isNotEmpty)
                        Text('Phone: ${invoice.customerContactPhone}'),
                    ],
                  ),
                  if (invoice.supplier != null && invoice.supplier!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _InfoCard(
                      title: 'Supplier',
                      children: [
                        Text(invoice.supplier!),
                        if (invoice.supplierAddress != null && invoice.supplierAddress!.isNotEmpty)
                          Text('Address: ${invoice.supplierAddress}'),
                        if (invoice.supplierContactEmail != null && invoice.supplierContactEmail!.isNotEmpty)
                          Text('Email: ${invoice.supplierContactEmail}'),
                        if (invoice.supplierContactPhone != null && invoice.supplierContactPhone!.isNotEmpty)
                          Text('Phone: ${invoice.supplierContactPhone}'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  _InfoCard(
                    title: 'Invoice details',
                    children: [
                      Text('Issued: ${invoice.issuedOn.toLocal().toString().split(' ').first}'),
                      if (invoice.dueDate != null) Text('Due: ${invoice.dueDate!.toLocal().toString().split(' ').first}'),
                      if (invoice.paymentTerms != null && invoice.paymentTerms!.isNotEmpty)
                        Text('Payment terms: ${invoice.paymentTerms}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    title: 'Financials',
                    children: [
                      Text('Subtotal: ${invoice.currency} ${invoice.subtotal.toStringAsFixed(2)}'),
                      Text('Discount: ${invoice.currency} ${invoice.discountAmount.toStringAsFixed(2)}'),
                      Text('Tax: ${invoice.currency} ${invoice.taxAmount.toStringAsFixed(2)}'),
                      Text('Total: ${invoice.currency} ${invoice.amount.toStringAsFixed(2)}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (invoice.notes != null && invoice.notes!.isNotEmpty)
                    _InfoCard(
                      title: 'Notes',
                      children: [Text(invoice.notes!)],
                    ),
                  const SizedBox(height: 12),
                  if (invoice.lineItems.isNotEmpty) ...[
                    _InfoCard(
                      title: 'Line items',
                      children: invoice.lineItems
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.lineNumber}. ${item.description}',
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  Text('${item.quantity} x ${item.unitPrice.toStringAsFixed(2)}'),
                                  const SizedBox(width: 12),
                                  Text('${invoice.currency} ${item.lineTotal.toStringAsFixed(2)}'),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => InvoiceEditPage(
                              invoiceId: invoice.id,
                              token: widget.token,
                              onLogout: widget.onLogout,
                              onSave: () async {
                                await _refresh();
                              },
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit Invoice'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class InvoiceEditPage extends StatefulWidget {
  const InvoiceEditPage({
    super.key,
    required this.invoiceId,
    required this.token,
    required this.onLogout,
    required this.onSave,
  });

  final int invoiceId;
  final String token;
  final Future<void> Function() onLogout;
  final Future<void> Function() onSave;

  @override
  State<InvoiceEditPage> createState() => _InvoiceEditPageState();
}

class _InvoiceEditPageState extends State<InvoiceEditPage> {
  late Future<InvoiceDetail> _detailFuture;
  final _customerAddressController = TextEditingController();
  final _customerEmailController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _supplierController = TextEditingController();
  final _supplierAddressController = TextEditingController();
  final _supplierEmailController = TextEditingController();
  final _supplierPhoneController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _paymentTermsController = TextEditingController();
  final _discountAmountController = TextEditingController();
  final _discountPercentageController = TextEditingController();
  final _taxPercentageController = TextEditingController();
  final _notesController = TextEditingController();
  final _lineDescriptionController = TextEditingController();
  final _lineQuantityController = TextEditingController();
  final _lineUnitPriceController = TextEditingController();
  final _lineTaxPctController = TextEditingController();
  final _lineDiscountPctController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _detailFuture = AuthService.fetchInvoiceDetail(widget.invoiceId);
  }

  void _populateFields(InvoiceDetail invoice) {
    _customerAddressController.text = invoice.customerAddress ?? '';
    _customerEmailController.text = invoice.customerContactEmail ?? '';
    _customerPhoneController.text = invoice.customerContactPhone ?? '';
    _supplierController.text = invoice.supplier ?? '';
    _supplierAddressController.text = invoice.supplierAddress ?? '';
    _supplierEmailController.text = invoice.supplierContactEmail ?? '';
    _supplierPhoneController.text = invoice.supplierContactPhone ?? '';
    _dueDateController.text = invoice.dueDate?.toIso8601String().split('T').first ?? '';
    _paymentTermsController.text = invoice.paymentTerms ?? '';
    _discountAmountController.text = invoice.discountAmount.toStringAsFixed(2);
    _discountPercentageController.text = invoice.discountPercentage.toStringAsFixed(2);
    _taxPercentageController.text = invoice.taxPercentage.toStringAsFixed(2);
    _notesController.text = invoice.notes ?? '';
  }

  Future<void> _saveInvoice() async {
    final payload = {
      'customerAddress': _customerAddressController.text.trim().isEmpty ? null : _customerAddressController.text.trim(),
      'customerContactEmail': _customerEmailController.text.trim().isEmpty ? null : _customerEmailController.text.trim(),
      'customerContactPhone': _customerPhoneController.text.trim().isEmpty ? null : _customerPhoneController.text.trim(),
      'supplier': _supplierController.text.trim().isEmpty ? null : _supplierController.text.trim(),
      'supplierAddress': _supplierAddressController.text.trim().isEmpty ? null : _supplierAddressController.text.trim(),
      'supplierContactEmail': _supplierEmailController.text.trim().isEmpty ? null : _supplierEmailController.text.trim(),
      'supplierContactPhone': _supplierPhoneController.text.trim().isEmpty ? null : _supplierPhoneController.text.trim(),
      'dueDate': _dueDateController.text.trim().isEmpty ? null : _dueDateController.text.trim(),
      'paymentTerms': _paymentTermsController.text.trim().isEmpty ? null : _paymentTermsController.text.trim(),
      'discountAmount': _discountAmountController.text.trim().isEmpty ? null : double.tryParse(_discountAmountController.text.trim()),
      'discountPercentage': _discountPercentageController.text.trim().isEmpty ? null : double.tryParse(_discountPercentageController.text.trim()),
      'taxPercentage': _taxPercentageController.text.trim().isEmpty ? null : double.tryParse(_taxPercentageController.text.trim()),
      'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    };

    try {
      await AuthService.updateInvoiceInfo(widget.invoiceId, payload);
      await widget.onSave();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice updated successfully')),
        );
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving invoice: $error')),
        );
      }
    }
  }

  Future<void> _addLineItem(InvoiceDetail invoice) async {
    final description = _lineDescriptionController.text.trim();
    final quantity = _lineQuantityController.text.trim();
    final price = _lineUnitPriceController.text.trim();

    if (description.isEmpty || quantity.isEmpty || price.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description, quantity, and unit price are required')),
      );
      return;
    }

    try {
      await AuthService.addLineItem(widget.invoiceId, {
        'description': description,
        'quantity': double.parse(quantity),
        'unitPrice': double.parse(price),
        'taxPercentage': _lineTaxPctController.text.trim().isEmpty ? null : double.parse(_lineTaxPctController.text.trim()),
        'discountPercentage': _lineDiscountPctController.text.trim().isEmpty ? null : double.parse(_lineDiscountPctController.text.trim()),
      });

      _lineDescriptionController.clear();
      _lineQuantityController.clear();
      _lineUnitPriceController.clear();
      _lineTaxPctController.clear();
      _lineDiscountPctController.clear();

      setState(() {
        _detailFuture = AuthService.fetchInvoiceDetail(widget.invoiceId);
      });
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding line item: $error')),
      );
    }
  }

  Future<void> _deleteLineItem(int lineItemId) async {
    try {
      await AuthService.deleteLineItem(widget.invoiceId, lineItemId);
      setState(() {
        _detailFuture = AuthService.fetchInvoiceDetail(widget.invoiceId);
      });
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting line item: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Invoice'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await widget.onLogout();
            },
          ),
        ],
      ),
      body: FutureBuilder<InvoiceDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _detailFuture = AuthService.fetchInvoiceDetail(widget.invoiceId);
                });
              },
            );
          }

          final invoice = snapshot.data!;
          _populateFields(invoice);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoCard(
                  title: 'Customer and supplier',
                  children: [
                    TextField(
                      controller: _customerAddressController,
                      decoration: const InputDecoration(labelText: 'Customer address'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customerEmailController,
                      decoration: const InputDecoration(labelText: 'Customer email'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customerPhoneController,
                      decoration: const InputDecoration(labelText: 'Customer phone'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _supplierController,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _supplierAddressController,
                      decoration: const InputDecoration(labelText: 'Supplier address'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _supplierEmailController,
                      decoration: const InputDecoration(labelText: 'Supplier email'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _supplierPhoneController,
                      decoration: const InputDecoration(labelText: 'Supplier phone'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  title: 'Dates and terms',
                  children: [
                    TextField(
                      controller: _dueDateController,
                      decoration: const InputDecoration(labelText: 'Due date (YYYY-MM-DD)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _paymentTermsController,
                      decoration: const InputDecoration(labelText: 'Payment terms'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  title: 'Financials',
                  children: [
                    TextField(
                      controller: _discountAmountController,
                      decoration: const InputDecoration(labelText: 'Discount amount'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _discountPercentageController,
                      decoration: const InputDecoration(labelText: 'Discount %'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _taxPercentageController,
                      decoration: const InputDecoration(labelText: 'Tax %'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  title: 'Notes',
                  children: [
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(labelText: 'Invoice notes'),
                      maxLines: 3,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  title: 'Line items',
                  children: [
                    for (final item in invoice.lineItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${item.description} • ${item.quantity} x ${item.unitPrice.toStringAsFixed(2)}'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteLineItem(item.id),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _lineDescriptionController,
                      decoration: const InputDecoration(labelText: 'Line description'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _lineQuantityController,
                            decoration: const InputDecoration(labelText: 'Qty'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _lineUnitPriceController,
                            decoration: const InputDecoration(labelText: 'Unit price'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _lineTaxPctController,
                            decoration: const InputDecoration(labelText: 'Tax %'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _lineDiscountPctController,
                            decoration: const InputDecoration(labelText: 'Disc %'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _addLineItem(invoice),
                        child: const Text('Add line item'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save),
                    onPressed: _saveInvoice,
                    label: const Text('Save changes'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InvoiceHeader extends StatelessWidget {
  const _InvoiceHeader({required this.invoice});

  final InvoiceDetail invoice;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.number,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(invoice.status),
              ],
            ),
            Chip(
              label: Text(invoice.status),
              backgroundColor: Theme.of(context).colorScheme.primary,
              labelStyle: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _LoginPage extends StatefulWidget {
  const _LoginPage({required this.onLoggedIn});

  final ValueChanged<String> onLoggedIn;

  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController(text: 'admin');
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final token = await AuthService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      widget.onLoggedIn(token);
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _formKey,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded, size: 64),
                      const SizedBox(height: 12),
                      const Text('Invoice Login', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(labelText: 'Username'),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Enter username' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Password'),
                        validator: (value) => value == null || value.isEmpty ? 'Enter password' : null,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _submitLogin,
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: Text(_loading ? 'Signing in...' : 'Login'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.onTap, required this.onDelete});

  final InvoiceSummary invoice;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Text(invoice.customer.isNotEmpty ? invoice.customer.substring(0, 1).toUpperCase() : 'I'),
        ),
        title: Text(invoice.number),
        subtitle: Text('${invoice.customer} • ${invoice.issuedOn.toLocal().toString().split(' ').first}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${invoice.currency} ${invoice.amount.toStringAsFixed(2)}'),
                Text(invoice.status, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete invoice', onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _StatusActions extends StatelessWidget {
  const _StatusActions({required this.invoice, required this.onChanged});

  final InvoiceDetail invoice;
  final Future<void> Function() onChanged;

  List<String> get _nextStatuses => switch (invoice.status) {
    'DRAFT' => ['SUBMITTED'],
    'SUBMITTED' => ['APPROVED', 'REJECTED'],
    'APPROVED' => ['PAID'],
    'REJECTED' => ['DRAFT', 'SUBMITTED'],
    _ => [],
  };

  @override
  Widget build(BuildContext context) {
    if (_nextStatuses.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      children: _nextStatuses.map((status) => OutlinedButton(
        onPressed: () async {
          String? reason;
          if (status == 'REJECTED') {
            reason = await showDialog<String>(
              context: context,
              builder: (context) {
                final controller = TextEditingController();
                return AlertDialog(
                  title: const Text('Reject invoice'),
                  content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Reason')),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Reject'))],
                );
              },
            );
            if (reason == null || reason.trim().isEmpty) return;
          }
          try {
            await AuthService.updateStatus(invoice.id, status, rejectionReason: reason);
            await onChanged();
          } catch (error) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update status: $error')));
          }
        },
        child: Text(status == 'SUBMITTED' ? 'Submit' : status[0] + status.substring(1).toLowerCase()),
      )).toList(),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text('The invoice service is unavailable.\n$message'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
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
  final _customerController = TextEditingController();
  final _amountController = TextEditingController();
  String _currency = 'EUR';

  @override
  void dispose() {
    _customerController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New invoice'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _customerController,
              decoration: const InputDecoration(labelText: 'Customer'),
              validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                return amount == null || amount <= 0 ? 'Enter a positive amount' : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: const [
                DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                DropdownMenuItem(value: 'USD', child: Text('USD')),
              ],
              onChanged: (value) => setState(() => _currency = value ?? 'EUR'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop((
                customer: _customerController.text.trim(),
                amount: double.parse(_amountController.text),
                currency: _currency,
              ));
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

extension IterableExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
