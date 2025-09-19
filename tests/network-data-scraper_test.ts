import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
  name: "Ensure data submission works correctly",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const dataSubmitter = accounts.get('wallet_1')!;

    let block = chain.mineBlock([
      Tx.contractCall(
        'network-data-scraper', 
        'submit-network-data', 
        [
          types.utf8('bandwidth-usage'),
          types.utf8('mainnet-test'),
          types.utf8('{"total_bandwidth": 1024}'),
          types.uint(2000)
        ], 
        dataSubmitter.address
      )
    ]);

    assertEquals(block.receipts.length, 1);
    assertEquals(block.height, 2);
    block.receipts[0].result.expectOk().expectUint(1);
  },
});

Clarinet.test({
  name: "Prevent insufficient stake submissions",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const dataSubmitter = accounts.get('wallet_1')!;

    let block = chain.mineBlock([
      Tx.contractCall(
        'network-data-scraper', 
        'submit-network-data', 
        [
          types.utf8('bandwidth-usage'),
          types.utf8('mainnet-test'),
          types.utf8('{"total_bandwidth": 1024}'),
          types.uint(100) // Below minimum stake
        ], 
        dataSubmitter.address
      )
    ]);

    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectErr().expectUint(103); // ERR-INSUFFICIENT-STAKE
  },
});