use anchor_lang::prelude::*;
use anchor_spl::token::{ Token, TokenAccount, Transfer };

declare_id!("YourProgramIDHere...");

#[program]
pub mod crosschain_vault {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
        Ok(())
    }

    pub fn unlock_with_merkle(
        ctx: Context<UnlockWithMerkle>,
        user: Pubkey,
        amount: u64,
        burn_id: [u8; 32],
        merkle_root: [u8; 32],
        proof: Vec<[u8; 32]>,
        leaf: [u8; 32],
    ) -> Result<()> {
        // Prevent replay
        let processed = &mut ctx.accounts.processed;
        require!(!processed.used.contains(&burn_id), ErrorCode::AlreadyProcessed);
        // Verify Merkle inclusion
        let valid = solana_program::merkle_tree::verify_merkle_proof(
            &proof, &merkle_root, &leaf,
        );
        require!(valid, ErrorCode::InvalidProof);

        // Mark as used
        processed.used.push(burn_id);

        // Transfer from vault to user token account
        let vault = &ctx.accounts.vault;
        let user_ata = &ctx.accounts.user_ata;
        let cpi = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: vault.to_account_info(),
                to: user_ata.to_account_info(),
                authority: ctx.accounts.pda_signer.to_account_info(),
            },
        );
        anchor_spl::token::transfer(cpi, amount)?;
        Ok(())
    }

    // For ZK unlocks—we assume zkVerifier is attached off-chain or via CPI
    pub fn unlock_with_zk(
        _ctx: Context<UnlockWithZk>,
        user: Pubkey,
        amount: u64,
        burn_id: [u8; 32],
        // zk proof bytes, input args here as needed
    ) -> Result<()> {
        // similar replay check + zk verification logic
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = payer, space = 8 + Vault::SIZE, seeds = [b"vault"], bump)]
    pub vault: Account<'info, Vault>,
    #[account(init, payer = payer, space = 8 + Processed::SIZE, seeds=[b"processed"], bump)]
    pub processed: Account<'info, Processed>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UnlockWithMerkle<'info> {
    #[account(mut, seeds=[b"vault"], bump)]
    pub vault: Account<'info, Vault>,
    #[account(mut, seeds=[b"processed"], bump)]
    pub processed: Account<'info, Processed>,
    /// CHECK: PDA signer for vault authority
    #[account(seeds=[b"vault"], bump)]
    pub pda_signer: UncheckedAccount<'info>,
    #[account(mut)]
    pub user_ata: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[account]
pub struct Vault {
    // Empty, logic uses SPL TokenAccount
    pub dummy: u8,
}

#[account]
pub struct Processed {
    pub used: Vec<[u8; 32]>,
}

// Custom errors
#[error_code]
pub enum ErrorCode {
    #[msg("Burn ID already processed")]
    AlreadyProcessed,
    #[msg("Invalid Merkle proof" )]
    InvalidProof,
}
