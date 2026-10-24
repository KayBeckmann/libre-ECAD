import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:shared_server_kit/shared_server_kit.dart';
import 'package:company_users_service/src/models.dart';
import 'package:company_users_service/src/repository_memory.dart';
import 'package:company_users_service/src/router.dart';
import 'package:company_users_service/src/workspace/store.dart';

void main() {
  late InMemoryCompanyUserRepository users;
  late MemoryWorkspaceStore store;
  late Handler handler;
  final tokens=<String,String>{};
  Future<void> account(String id,String company,UserRole role) async {
    final created=await users.createUser(id:id,companyId:company,username:id,role:role);
    await users.activateWithToken(rawToken:created.rawActivationToken,passwordHash:'test-hash');
    final token=SessionTokens.generate();tokens[id]=token;
    await users.saveSession(UserSession(tokenHash:SessionTokens.hashOf(token),userId:id,companyId:company,
      createdAt:DateTime.now(),expiresAt:DateTime.now().add(const Duration(hours:1))));
  }
  Future<Response> call(String user,String method,String path,[Object? body]) async =>handler(Request(method,
    Uri.parse('http://localhost/api/v1/$path'),headers:{'authorization':'Bearer ${tokens[user]}'},body:body==null?null:jsonEncode(body)));
  Future<Map<String,dynamic>> json(Response r) async=>jsonDecode(await r.readAsString()) as Map<String,dynamic>;
  setUp(() async {
    users=InMemoryCompanyUserRepository();store=MemoryWorkspaceStore();
    await users.createCompany(id:'a',name:'Firma A');await users.createCompany(id:'b',name:'Firma B');
    await account('admin-a','a',UserRole.admin);await account('admin-b','b',UserRole.admin);
    await account('drafter-a','a',UserRole.zeichner);
    handler=CompanyUserRouter(repository:users,internalToken:'test',workspace:store).handler.call;
  });
  test('same project names do not cross company boundaries, including direct IDs',() async {
    final a=await json(await call('admin-a','POST','projects',{'name':'Verteilung'}));
    final b=await json(await call('admin-b','POST','projects',{'name':'Verteilung'}));
    expect(a['id'],isNot(b['id']));
    final own=await json(await call('admin-a','GET','projects'));
    expect((own['projects'] as List).length,1);
    expect((await call('admin-a','GET','projects/${b['id']}')).statusCode,404);
    expect((await call('admin-a','PATCH','projects/${b['id']}',{'name':'Hacked','version':1})).statusCode,404);
  });
  test('drafter needs membership; cannot create projects or grant membership',() async {
    final p=await json(await call('admin-a','POST','projects',{'name':'Test'}));
    expect((await call('drafter-a','GET','projects/${p['id']}')).statusCode,404);
    expect((await call('drafter-a','POST','projects',{'name':'Test'})).statusCode,403);
    expect((await call('admin-a','PATCH','projects/${p['id']}',{...p,'memberIds':['drafter-a']})).statusCode,200);
    expect((await call('drafter-a','GET','projects/${p['id']}')).statusCode,200);
    expect((await call('drafter-a','PATCH','projects/${p['id']}',{'name':'Test','version':2,'memberIds':[]})).statusCode,403);
    expect((await call('drafter-a','PATCH','projects/${p['id']}',{'name':'Changed','version':2})).statusCode,200);
  });
  test('stale updates return conflict and keep newer data and history intact',() async {
    final p=await json(await call('admin-a','POST','projects',{'name':'Original'}));
    expect((await call('admin-a','PATCH','projects/${p['id']}',{'name':'New','version':1})).statusCode,200);
    expect((await call('admin-a','PATCH','projects/${p['id']}',{'name':'Stale','version':1})).statusCode,409);
    expect((await json(await call('admin-a','GET','projects/${p['id']}')))['name'],'New');
    expect((await store.history('a','project',p['id'] as String)).length,2);
  });
  test('foreign members and malformed data are rejected without persistence',() async {
    expect((await call('admin-a','POST','projects',{'name':'Test','memberIds':['admin-b']})).statusCode,400);
    expect((await call('admin-a','POST','projects',{'name':42})).statusCode,400);
    expect((await call('admin-a','POST','projects',[])).statusCode,400);
    expect(await store.list('a','project'),isEmpty);
  });
  test('deactivated user cannot use a previously issued session',() async {
    await users.setUserActive(id:'drafter-a',active:false);
    expect((await call('drafter-a','GET','projects')).statusCode,401);
  });
}
